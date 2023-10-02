#! /usr/bin/env ruby

require 'nuggets/json/multi'
require 'nuggets/json/canonical'

if $0 == __FILE__
  if ARGV.include?('-h') || ARGV.include?('--help')
    abort "Usage: #{$0} [-h|--help] [{-l|--lines}|{-r|--records}] [-c|--canonical] [SOURCE...]"
  end

  method = ARGV.delete('--canonical') || ARGV.delete('-c') ? :pc : :pp

  print = ->(source) { puts begin
    JSON.send(method, source)
  rescue JSON::ParserError => err
    warn "#{err.class}: #{err}"
    source
  end }

  if ARGV.delete('--records') || ARGV.delete('-r')
    record = ''

    ARGF.each { |line|
      record << line

      if /\A}/.match?(line)
        print[record]
        record.clear
      end
    }
  elsif ARGV.delete('--lines') || ARGV.delete('-l')
    ARGF.each(&print)
  else
    print[ARGF.read]
  end
end
