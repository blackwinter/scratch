#! /usr/bin/ruby

abort "Usage: #{$0} <in.syn>... <out.syn>" unless ARGV.size >= 2

STDOUT.sync = true

KEY_SEPARATOR   = '*'.freeze
VALUE_SEPARATOR = '|'.freeze

merge = Hash.new { |h, k| h[k] = [] }
outfile = ARGV.pop

# first run sets the basis!
File.foreach(ARGV.shift) { |line|
  print '.' if $. % 1_000 == 0

  line.chomp!

  key, values = line.split(KEY_SEPARATOR, 2)
  merge[key] = values.split(VALUE_SEPARATOR)
}

keys = merge.keys

puts

ARGV.each { |syn|
  _keys = []

  File.foreach(syn) { |line|
    print '.' if $. % 1_000 == 0

    line.chomp!

    key, values = line.split(KEY_SEPARATOR, 2)
    merge[key] &= values.split(VALUE_SEPARATOR)

    _keys << key
  }

  keys &= _keys

  puts
}

merge.delete_if { |key, values|
  values.empty? || !keys.include?(key)
}

puts

File.open(outfile, 'w') { |f|
  merge.sort.each_with_index { |(key, values), i|
    print '.' if i % 1_000 == 0

    f.puts "#{key}#{KEY_SEPARATOR}#{values.sort.join(VALUE_SEPARATOR)}"
  }
}

puts
