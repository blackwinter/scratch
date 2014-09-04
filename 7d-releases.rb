#! /usr/bin/env ruby

#--
###############################################################################
#                                                                             #
# 7d-releases -- Query 7digital for releases by artist(s)                     #
#                                                                             #
# Copyright (C) 2014 Jens Wille                                               #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@gmail.com>                                       #
#                                                                             #
# 7d-releases is free software; you can redistribute it and/or modify it      #
# under the terms of the GNU Affero General Public License as published by    #
# the Free Software Foundation; either version 3 of the License, or (at your  #
# option) any later version.                                                  #
#                                                                             #
# 7d-releases is distributed in the hope that it will be useful, but WITHOUT  #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or       #
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License #
# for more details.                                                           #
#                                                                             #
# You should have received a copy of the GNU Affero General Public License    #
# along with 7d-releases. If not, see <http://www.gnu.org/licenses/>.         #
#                                                                             #
###############################################################################
#++

# Sample cron.weekly script:
#
#   #! /bin/bash
#   ~/7d-releases -k ~/.7d.key -c GB -d `date +%F -d '1 week ago'` foo bar baz

require 'sevendigital'

class SevendigitalReleases

  include Enumerable

  DEFAULT_COUNTRY = 'US'

  RELEASE_OPTIONS = { type: 'album', page_size: 50 }

  def initialize(name, key, country = nil, &block)
    raise 'API key missing' if key.nil? || key.empty?

    @name, @block = name.to_s.tr('_', ' '), block || :first.to_proc

    @exact = /\A#{Regexp.escape(@name).gsub('\ ', '.')}\z/i

    @key, @country = key, country || DEFAULT_COUNTRY

    reset
  end

  attr_reader :name

  def reset
    @artist, @releases, @client = nil, nil,
      Sevendigital::Client.new(oauth_consumer_key: key, country: country)
  end

  def artist
    @artist ||= find_artist
  end

  def releases
    @releases ||= find_releases
  end

  def each(&block)
    releases.each(&block)
  end

  def inspect
    '#<%s:0x%x %s>' % [self.class, object_id, name]
  end

  private

  attr_reader :block, :exact, :key, :country, :client

  def find_artist
    artists, re = client.artist.browse(name), exact
    raise "Artist not found: #{name}" if artists.empty?

    artists.find { |artist| artist.name =~ re } || if artists.size > 1
      artists.group_by(&:name).fetch(block[artists.map(&:name)]).first
    else
      artists.first
    end
  end

  def find_releases
    releases, page, artist = [], 0, self.artist

    loop {
      _releases = artist.get_releases(RELEASE_OPTIONS.merge(page: page += 1))
      _releases.empty? ? break : releases.concat(_releases)
    }

    releases.sort_by(&:release_date)
  end

end

if $0 == __FILE__

  require 'date'
  require 'highline/import'
  require 'nuggets/argv/option'

  USAGE = <<-EOT
Usage: #{$0} [-k <key-file>] [-c <country>] [-d <date:YYYY-MM-DD>] <artist>...
  EOT

  abort USAGE if ARGV.empty?

  def handle_error(usage = false)
    yield
  rescue => err
    $VERBOSE ? raise : usage ? abort("#{err}\n#{USAGE}") : warn(err.to_s)
  end

  def handle_option(*args, &block)
    handle_error(true) { ARGV.option!(*args, &block) }
  end

  key = handle_option(:k, :key) { |k|
    File.read(File.expand_path(k)).chomp } || ENV['SEVENDIGITAL_API_KEY']

  if $stdin.tty?
    key ||= ask('API key: ')
    block = lambda { |names| choose(*names) }
  end

  date = handle_option(:d, :date) { |d| Date.strptime(d, '%Y-%m-%d') }

  country = handle_option(:c, :country) || ENV['SEVENDIGITAL_COUNTRY']

  ARGV.each { |name| handle_error {
    SevendigitalReleases.new(name, key, country, &block).each { |release|
      puts release.url unless date && release.release_date < date
    }

    sleep 1
  } }

end
