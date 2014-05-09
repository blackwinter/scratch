#! /usr/bin/env ruby

#--
###############################################################################
#                                                                             #
# google_calendar_sync -- (One-way) Sync Google Calendar with local ICS       #
#                                                                             #
# Copyright (C) 2014 Jens Wille                                               #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@gmail.com>                                       #
#                                                                             #
# google_calendar_sync is free software; you can redistribute it and/or       #
# modify it under the terms of the GNU Affero General Public License as       #
# published by the Free Software Foundation; either version 3 of the License, #
# or (at your option) any later version.                                      #
#                                                                             #
# google_calendar_sync is distributed in the hope that it will be useful, but #
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY  #
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public      #
# License for more details.                                                   #
#                                                                             #
# You should have received a copy of the GNU Affero General Public License    #
# along with google_calendar_sync. If not, see http://www.gnu.org/licenses/.  #
#                                                                             #
###############################################################################
#++

# TODO: logging

require 'nuggets/env/user_home'
require 'google/api_client'
require 'icalendar'
require 'json'
require 'time'

class GoogleCalendarSync

  VERSION = '0.2'

  DEFAULT_CFG = File.join(ENV.user_home, '.google_calendar_sync.json')

  DEFAULT_CID = 'primary'

  DEFAULT_MIN = DateTime.now - 180

  CANCEL = JSON.dump('status' => 'cancelled').freeze

  class << self

    def sync(*args)
      new(*args).sync(true)
    end

    def argv(argv = ARGV, prog = $0, options = {})
      require 'optparse'

      OptionParser.new { |opts|
        opts.banner = "Usage: #{prog} [-h|--help] [options] <ics>"

        opts.separator ' '
        opts.separator 'Options:'

        opts.on('-c', '--config PATH', "Path to config file [Default: #{DEFAULT_CFG}]") { |c|
          options[:cfg] = c
        }

        opts.on('-i', '--cid STRING', "Calendar ID to operate on [Default: #{DEFAULT_CID}]") { |i|
          options[:cid] = i
        }

        opts.separator ' '
        opts.separator 'Generic options:'

        opts.on('-v', '--verbose', 'Be verbose') {
          options[:verbose] = true
        }

        opts.on('-h', '--help', 'Print this help message and exit') {
          puts opts
          exit
        }

        opts.on('--version', 'Print program version and exit') {
          puts "#{File.basename(prog, '.rb')} v#{VERSION}"
          exit
        }
      }.parse!(argv)

      [argv.shift || abort("#{prog}: ICS file required!"), options]
    end

  end

  def initialize(ics, options = {})
    @ics, @cfg, @cid, @min, @verbose = ics,
      options[:cfg] || DEFAULT_CFG,
      options[:cid] || DEFAULT_CID,
      options[:min] || DEFAULT_MIN,
      options[:verbose]
  end

  attr_reader :ics, :cfg

  attr_accessor :cid, :min, :verbose

  def clear(&block)
    handle_error(execute(:calendars, :clear), &block)
    self
  end

  def sync(clear = false)
    clear ? self.clear { _sync(true) } : _sync
    self
  end

  def each_item(params = { 'timeMin' => min }, &block)
    return enum_for(:each_item, params) unless block_given?

    handle_error(execute(:events, :list, parameters: params)) { |result|
      iterate_items(result, &block)

      if page_token = result.data.next_page_token
        each_item(params.merge('pageToken' => page_token), &block)
      end
    }

    self
  end

  def each_event
    return enum_for(:each_event) unless block_given?

    dt_hash = lambda { |datetime|
      { 'dateTime' => dt(datetime), 'timeZone' => tzid }
    }

    ical.events.each { |event|
      event.extend(EventExt).dt_hash = dt_hash
      yield event
    }

    self
  end

  def inspect
    '#<%s:0x%x @ics=%p, @cfg=%p, @cid=%p>' % [
      self.class, object_id, ics, cfg, cid
    ]
  end

  private

  def ical
    @ical ||= File.open(ics) { |f| Icalendar::Parser.new(f, false).parse.first }
  end

  def tzid
    @tzid ||= ical.timezones.first.tzid
  end

  def tz
    @tz ||= TZInfo::Timezone.get(tzid)
  end

  def dt(datetime)
    tz.local_to_utc(datetime.to_datetime)
  end

  def dd(datetime)
    datetime.to_s[/[^T ]*/]
  end

  def config
    @config ||= JSON.load(File.read(File.expand_path(cfg)))
  end

  def client
    @client ||= authorize(Google::APIClient.new(
      application_name:    self.class.name,
      application_version: VERSION
    ))
  end

  def authorize(client = @client)
    auth = client.authorization

    config.each { |key, value|
      value = Time.parse(value) if key.end_with?('_at')
      auth.send("#{key}=", value)
    }

    unless auth.access_token && !auth.expired?
      unless auth.access_token && auth.refresh_token
        abort 'Authorization required.' unless $stdin.tty?

        puts auth.authorization_uri
        puts 'Code: '

        auth.code = gets.strip
        exit if auth.code.empty?
      end

      auth.fetch_access_token!

      File.open(File.expand_path(cfg), 'w') { |f|
        JSON.dump(config.update(
          'refresh_token' => auth.refresh_token,
          'access_token'  => auth.access_token,
          'expires_at'    => auth.expires_at
        ), f)
      }
    end

    client
  end

  def calendar_api(v = 3)
    @calendar_api ||= client.discovered_api('calendar', "v#{v}")
  end

  def calendar_params(*args)
    merge_params(args.last.is_a?(Hash) ? args.pop : {},
      api_method: args.inject(calendar_api) { |obj, key| obj.send(key) },
      parameters: { 'calendarId' => cid, 'sendNotifications' => true },
      headers:    { 'Content-Type' => 'application/json' }
    )
  end

  def merge_params(a, b)
    a.merge(b) { |k, o, n| o.is_a?(Hash) && n.is_a?(Hash) ? o.merge(n) : n }
  end

  def execute(*args)
    client.execute(calendar_params(*args))
  end

  def handle_error(result, batch = nil)
    if result.error?
      warn result.error_message
      warn result.inspect if verbose
    else
      yield result if block_given?
    end

    result
  end

  def exceptions
    @exceptions ||= Hash.new { |h, k| h[k] = [] }
  end

  def recurrences
    @recurrences ||= {}
  end

  def batch(method, hash = nil)
    execute = client.method(:execute)

    _params = calendar_params(:events, method)
    params  = lambda { |_hash| merge_params(_params, _hash) }

    yield batch = Batch.new(execute, params, &batch_block(hash, batch))
  ensure
    batch.flush if batch
  end

  def batch_block(hash, batch = nil)
    block = lambda { |arg| send(*hash.first.insert(1, arg)) if hash }
    batch ? lambda { |arg| handle_error(arg, batch, &block) } : block
  end

  def iterate_items(result)
    result.data['items'].each { |item| yield item.extend(ItemExt) }
  end

  def _sync(cleared = false)
    events, @exceptions, @recurrences = {}, nil, nil

    each_event { |event| events[event.gcs_id] = event }

    unless cleared
      batch(:delete) { |delete|
        batch(:patch) { |patch|
          each_item { |item|
            if event = item.find_event(events)
              item.batch(patch, event.to_params) if item.diff?(event)
            else
              item.batch(delete)
            end
          }
        }
      }
    end

    batch(:patch) { |cancel|
      batch(:instances, cancel: cancel) { |instances|
        batch(:insert, instances: instances) { |insert|
          events.each_value(&batch_block(insert: insert))
        }
      }
    }

    self
  end

  def cancel(result, batch)
    iterate_items(result) { |item|
      if exceptions[item.gcs_id].include?(dd(item['start']['dateTime']))
        item.batch(batch, body: CANCEL)
      end
    }
  end

  def instances(result, batch)
    item = result.data.extend(ItemExt)
    item.batch(batch) if exceptions.key?(item.gcs_id)
  end

  def insert(event, batch)
    return unless event.summary

    recurrences[event.uid] ||= event.gcs_id unless event.rrule.empty?

    if !event.exdate.empty?
      exceptions[event.gcs_id].concat(event.exdate.flatten.map(&method(:dd)))
    elsif id = recurrences[event.uid]
      exceptions[id] << dd(event.dtstart)
    end

    t = event.class.default_property_types['rrule']

    event.batch(batch,
      'recurrence' => event.rrule.map { |rrule| "RRULE#{rrule.to_ical(t)}" },
      'extendedProperties' => { 'private' => { 'gcs:uid' => event.gcs_id } })
  end

  module ItemExt

    def gcs_id
      self['extendedProperties']['private']['gcs:uid']
    end

    def find_event(events)
      if self['status'] == 'confirmed' && self['recurrence'].empty?
        events.delete(gcs_id)
      end
    end

    def to_params(hash = {})
      hash.merge(parameters: { 'eventId' => self['id'] })
    end

    def batch(batch, hash = {})
      batch[to_params(hash)]
    end

    def diff?(event)
      (hash = event.to_h).values != to_hash.values_at(*hash.keys)
    end

  end

  module EventExt

    def gcs_id
      @gcs_id ||= "#{uid}:#{dt_hash[created || last_modified]['dateTime']}"
    end

    attr_accessor :dt_hash

    def to_h(hash = {})
      hash.merge(
        'summary'     => summary,
        'location'    => location,
        'description' => description,
        'start'       => dt_hash[dtstart],
        'end'         => dt_hash[dtend]
      )
    end

    def to_params(hash = {})
      { body: JSON.dump(to_h(hash)) }
    end

    def batch(batch, hash = {})
      batch[to_params(hash)]
    end

  end

  class Batch

    MAX_SIZE = 50

    def initialize(execute, params, &block)
      @execute, @params, @batch = execute, params,
        Google::APIClient::BatchRequest.new(&block)
    end

    def [](hash)
      @batch.add(@params[hash])
      flush(MAX_SIZE)
    end

    def flush(size = 1)
      unless @batch.calls.size < size
        execute
        sleep 1
      end
    end

    def execute(retries = 5)
      @execute[@batch]
      @batch.calls.clear
    rescue Timeout::Error
      raise if retries.zero?

      sleep 120 / retries
      retries -= 1

      retry
    end

  end

end

GoogleCalendarSync.sync(*GoogleCalendarSync.argv) if $0 == __FILE__
