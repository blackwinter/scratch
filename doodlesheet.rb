#! /usr/bin/env ruby
# encoding: utf-8

require 'open-uri'
require 'spreadsheet'

class Doodle

  BASE_URL   = 'http://doodle.com'

  POLL_URL   = "#{BASE_URL}/%s"

  ADMIN_URL  = "#{POLL_URL}%s/admin"

  EXPORT_URL = "#{BASE_URL}/export/excel?pollId=%s&adminKey=%s"

  BASE_PATH  = File.expand_path('..', __FILE__)

  FILE_FMT   = 'doodle-%s-%s.xls'

  ANSWER = Hash.new { |h, k|
    h[k]   =  k
  }.update(
    ''     => 'No',
    'OK'   => 'Yes',
    '(OK)' => '(Yes)'
  )

  COLOUR = Hash.new { |h, k|
    h[k]    =  '#D0E3FB'
  }.update(
    'No'    => '#FFCCCA',
    'Yes'   => '#D1F3D1',
    '(Yes)' => '#FFEDA1'
  )

  MONTHS = Hash.new { |h, k|
    h[k]       =  k[0, 3]
  }.update(
    'März'     => 'Mar',
    'Mai'      => 'May',
    'Oktober'  => 'Oct',
    'Dezember' => 'Dec'
  )

  def self.run(action, argv)
    doodles, args = argv.partition { |i| i.include?('=') }
    doodles.each { |doodle| new(*doodle.split('=')).send(action, *args) }
  end

  def initialize(pid, key)
    @poll_url   = POLL_URL   % [pid]
    @admin_url  = ADMIN_URL  % [pid, key]
    @export_url = EXPORT_URL % [pid, key]

    @file_fmt = FILE_FMT % [pid, '%s']
    @date_re  = Regexp.new(@file_fmt % '(.*?)')
  end

  attr_reader :poll_url, :admin_url, :export_url

  def path(date = Date.today.strftime('%Y-%m-%d'))
    File.join(BASE_PATH, @file_fmt % date)
  end

  def date(path)
    File.basename(path ||= '[JUST NOW]')[@date_re, 1] || path
  end

  def list
    Dir[path('*')].sort
  end

  def fetch
    open(export_url)
  end

  def update(num = nil)
    res = if (last = list.last) != (path = self.path)
      xls = fetch.read; last && File.binread(last) == xls ?
        File.rename(last, path) : File.binwrite(path, xls)
    end

    clean(num) if num

    res
  end

  def clean(num)
    File.delete(*list.reverse.drop(Integer(num)))
  end

  def sheet(xls = nil)
    Sheet.new(xls || fetch)
  end

  def diff(xls1 = nil, xls2 = nil)
    sheet(xls1).diff(sheet(xls2))
  end

  def next
    @next ||= sheet.next
  end

  def report_diff
    report_internal { |state, *args|
      case state
        when :begin           then puts "======== #{args.first} ========\n\n"
        when :added, :deleted then puts "#{state.capitalize}: #{args.first}"
        when :changed
          case args.shift
            when :begin then puts 'Changed:'
            when :item
              case args.shift
                when :begin  then puts "- #{args.first}"
                when :key    then print "  - #{args.first}: "
                when :values then puts args.join(' => ')
              end
            when :end then puts
          end
      end
    }

    puts ">>>>>>>> #{poll_url} <<<<<<<<"
  end

  def report_html
    require 'erb'

    h = lambda { |*args| ERB::Util.h(*args) }

    c = lambda { |value|
      %Q{<span style="color: %s">%s</span>} % [COLOUR[value], h[value]]
    }

    next_key, next_entries = self.next

    unless next_entries.all?(&:empty?)
      puts %Q{<h2><a href="%s" class="plain">%s</a> [<a href="%s">%s</a>]</h2>\n<dl>} % [
        poll_url, h[next_key.reverse.join(' / ')], admin_url, 'Admin'
      ]

      d = lambda { |(key, values)|
        puts "<dt>#{c[key]}</dt><dd>#{h[values.join(', ')]}</dd>"
      }

      %w[Yes (Yes) No].each { |key|
        names = next_entries.delete(ANSWER.key(key))
        d[[key, names]] unless names.nil? || names.empty?
      }

      next_entries.each(&d)

      puts '</dl>'
    end

    report_internal(true) { |state, *args|
      case state
        when :begin           then puts "<h2>#{h[*args]}</h2>"
        when :added, :deleted then puts "<h3>#{state.capitalize}</h3>\n<p>#{h[*args]}</p>"
        when :changed
          case args.shift
            when :begin then puts "<h3>Changed</h3>\n<ul>"
            when :item
              case args.shift
                when :begin  then puts "<li><strong>#{h[*args]}</strong>\n<dl>"
                when :key    then puts "<dt>#{h[*args]}</dt>"
                when :values then puts "<dd>#{args.map(&c).join(h[' => '])}</dd>"
                when :end    then puts '</dl></li>'
              end
            when :end then puts '</ul>'
          end
      end
    }
  end

  private

  def report_internal(reverse = false)
    list.push(nil).each_cons(2).send(reverse ? :reverse_each : :each) { |xls|
      added, deleted, changed = diff(*xls)

      next if added.empty? && deleted.empty? && changed.empty?

      yield :begin, xls.map { |x| date(x) }.join(' : ')

      yield :added,   added.join(', ')   unless added.empty?
      yield :deleted, deleted.join(', ') unless deleted.empty?

      next if changed.empty?

      yield :changed, :begin

      changed.each { |name, changes|
        yield :changed, :item, :begin, name

        changes.each { |key, *values|
          yield :changed, :item, :key, key.reverse.join(' / ')
          yield :changed, :item, :values, *values.map(&ANSWER.method(:[]))
        }

        yield :changed, :item, :end
      }

      yield :changed, :end

      yield :end
    }
  end

  class Sheet < Hash

    def initialize(xls)
      delete = true

      sheet = Spreadsheet.open(xls, 'r').worksheets.first.to_a.delete_if { |row|
        if row.empty?; delete = !delete; true; else; delete; end
      }

      keys = sheet.slice!(0, 3)  # months, days, events
      keys.each(&:shift).reverse!; month = nil

      keys = keys.shift.zip(*keys).each { |key| month = key[2] ||= month }
      sheet.each { |name, *entries| self[name] = Hash[keys.zip(entries)] }
    end

    def diff(other)
      [other.keys - keys, keys - other.keys, Hash.new { |h, k| h[k] = [] }]
        .tap { |_, _, changed| each { |name, entries|
          other_entries = other[name] or next

          entries.each { |key, value|
            if other_value = other_entries[key] and value != other_value
              changed[name] << [key, value, other_value]
            end
          }
        } }
    end

    def next(date = Date.today)
      [key = next_key(date), Hash.new { |h, k| h[k] = [] }.tap { |hash|
        each { |name, entries| hash[entries[key]] << name }
      }]
    end

    private

    def next_key(date)
      first.last.keys.find { |_, day, month|
        Date.parse("#{day[/\d+/]} #{month.sub(/\S+/, MONTHS)}") >= date
      }
    end

  end

end

if $0 == __FILE__
  require 'nuggets/argv/option'

  Doodle.run(ARGV.switch!(:u) ? :update :
             ARGV.switch!(:H) ? :report_html :
                                :report_diff, ARGV)
end
