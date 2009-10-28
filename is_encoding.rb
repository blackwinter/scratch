#! /usr/bin/ruby

require 'iconv'

abort "Usage: #{$0} <enc> [-x|-d|-o|-s] <chr>..." if ARGV.size < 2

ICONV = begin
  Iconv.new(enc = ARGV.shift, enc)
rescue Iconv::InvalidEncoding
  abort "INVALID ENCODING: #{enc}"
end

def iconv(chr, inp = chr)
  ICONV.iconv(chr)
rescue Iconv::IllegalSequence, Iconv::InvalidCharacter => err
  abort "ILLEGAL INPUT SEQUENCE: #{err} [#{inp.inspect}]"
end

def base
  { :x => 16, :d => 10, :o => 8 }.find { |key, val|
    break val if ARGV.delete("-#{key}")
  }
end

if ARGV.delete('-s')
  ARGV.each { |chr|
    arg = [chr]
    arg.unshift(STDIN.read) if chr == '-'

    iconv(*arg)
  }
else
  bas = base || 16

  ARGV.each { |chr|
    begin
      iconv(chr.to_i(bas).chr, chr)
    rescue RangeError => err
      abort err
    end
  }
end
