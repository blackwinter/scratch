#! /usr/bin/ruby

#--
###############################################################################
#                                                                             #
# pwsafe -- Supposedly secure store for passwords and other secrets           #
#                                                                             #
# Copyright (C) 2008 Jens Wille                                               #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@uni-koeln.de>                                    #
#                                                                             #
# pwsafe is free software; you can redistribute it and/or modify it under the #
# terms of the GNU General Public License as published by the Free Software   #
# Foundation; either version 3 of the License, or (at your option) any later  #
# version.                                                                    #
#                                                                             #
# pwsafe is distributed in the hope that it will be useful, but WITHOUT ANY   #
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS   #
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more       #
# details.                                                                    #
#                                                                             #
# You should have received a copy of the GNU General Public License along     #
# with pwsafe. If not, see <http://www.gnu.org/licenses/>.                    #
#                                                                             #
###############################################################################
#++

abort "Sorry, must be root!" unless Process.uid.zero?

require 'optparse'
require 'yaml'

require 'openssl'
require 'digest/sha2'

require 'rubygems'
require 'highline'

# {{{ class Safe
class Safe

  FORBIDDEN = %r/[(){};'&=\\\n\r\t]/o

  attr_reader :file, :terminal

  def initialize(file, create = false)
    @file, @create = file, create

    @terminal = HighLine.new(STDIN, STDOUT.tty? ? STDOUT : STDERR)
  end

  def safe
    @safe ||= self.load
  end

  def [](realm = nil)
    safe[realm || choose_realm] || ''
  end

  def set(realm = nil, secret = nil)
    realm ||= choose_realm

    raise TypeError, "String expected, got #{realm.class}" unless realm.is_a?(String)
    raise ArgumentError, "Illegal value in #{realm.inspect}" if realm.empty? || realm =~ FORBIDDEN

    secret ||= ask_for_secret

    raise TypeError, "String expected, got #{secret.class}" unless secret.is_a?(String)
    raise ArgumentError, "Illegal value in #{secret.inspect}" if secret.empty?

    @modified = true
    safe[realm] = secret

    realm
  end

  alias_method :[]=, :set

  def delete(realm = nil)
    realm ||= choose_realm

    @modified = true
    safe.delete(realm)

    realm
  end

  def entries
    safe.keys.sort
  end

  def decrypt(content)
    crypt(:decrypt, content)
  end

  def encrypt(content)
    crypt(:encrypt, content)
  end

  def load
    if File.exists?(file)
      yaml = decrypt(File.read(file))

      safe = begin
        YAML.load(yaml)
      rescue ArgumentError
        raise CryptError
      end

      raise CryptError unless safe.is_a?(Hash)
      raise CryptError if safe.keys.any? { |k| k =~ FORBIDDEN }

      safe
    else
      create_missing
      {}
    end
  end

  def save
    File.open(file, 'w') { |f| f.write encrypt(YAML.dump(safe)) }
  end

  def open
    yield
    save if @modified
  end

  private

  def crypt(method, content)
    cipher = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
    cipher.send(method)  # decrypt/encrypt

    cipher.iv  = Digest::SHA256.hexdigest("--#{file}--#{iv}--")
    cipher.key = Digest::SHA256.hexdigest(key)

    cipher << content << cipher.final
  rescue OpenSSL::Cipher::CipherError
    raise CryptError
  end

  def key
    @key ||= ask_for('Key')
  end

  def iv
    @iv ||= ask_for('IV')
  end

  def ask_for(what, pw = true)
    terminal.ask("#{what}: ") { |q| q.echo = !pw }
  rescue Interrupt
    raise Abort
  end

  def ask_for_secret
    secret  = ask_for('Secret')
    confirm = ask_for('Re-type secret')

    raise SecretMismatchError unless secret == confirm

    secret
  end

  def choose_realm
    items  = Hash.new { |h, k| h[k] = k }
    length = entries.size.to_s.length

    entries.each_with_index { |entry, index|
      puts "%#{length}d) %s" % [index += 1, entry]
      items[index.to_s] = entry
    }

    items[ask_for('Realm', false)]
  rescue Interrupt, EOFError
    raise Abort
  end

  def create_missing
    raise FileNotFoundError unless @create

    File.open(file, 'w') { |f| f.chmod(0600) }
    @modified = true
  end

  class SafeError < StandardError; end

  class Abort               < SafeError; end
  class CryptError          < SafeError; end
  class FileNotFoundError   < SafeError; end
  class SecretMismatchError < SafeError; end

end
# }}}

# {{{ APPCODE
if $0 == __FILE__

USAGE = "Usage: #{$0} [-h|--help] [options] <file> [<realm>]"
abort USAGE if ARGV.empty?

# {{{ options
options = {}

OptionParser.new { |opts|
  opts.banner = USAGE

  opts.separator ' '
  opts.separator 'Options:'

  opts.on('-c', '--create', "Create a new file if it doesn't exist") {
    options[:create] = true
  }

  opts.separator ' '
  opts.separator 'Actions:'

  opts.on('-l', '--list', 'List all entries in the file') {
    options[:action] = 'list'
  }

  opts.on('-s', '--set', 'Set secret for the specified entry') {
    options[:action] = 'set'
  }

  opts.on('-D', '--delete', 'Delete the specified entry') {
    options[:action] = 'delete'
  }

  opts.separator ' '
  opts.separator 'Without any action, the secret is sent to STDOUT -- unencrypted! If realm'
  opts.separator 'is not given, it will be asked for interactively.'

  opts.separator ' '
  opts.separator "Realm should be of the form 'host:service:name' (or similar); it must not"
  opts.separator "contain any of the characters #{Safe::FORBIDDEN.source}."
}.parse!

# must have file and optional realm
abort USAGE unless (1..2).include?(ARGV.size)
# }}}

begin
  file   = File.expand_path(ARGV.shift)
  pwsafe = Safe.new(file, options[:create])

  # optional
  realm = ARGV.shift

  pwsafe.open do
    case options[:action]
      when 'list'
        puts pwsafe.entries
      when 'delete'
        puts pwsafe.delete(realm)
      when 'set'
        begin
          puts pwsafe.set(realm)
        rescue Safe::SecretMismatchError
          abort "Secrets don't match"
        end
      else
        secret = pwsafe[realm]

        if STDOUT.tty?
          puts secret.center(80, '#')

          clear = '/usr/bin/clear'
          system(clear) if File.executable?(clear)
        else
          puts secret
        end
    end
  end
rescue Safe::FileNotFoundError
  abort "File not found: #{file}; use '-c' to create it"
rescue Safe::Abort
  abort ''
rescue Safe::SafeError
  exit
rescue StandardError => err
  abort err
end

end
# }}}

# vim:fdm=marker:fen
