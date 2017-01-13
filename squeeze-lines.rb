#! /usr/bin/env ruby

lines = ARGF.each_line.map(&:chomp)

lines.shift while lines.first.empty?
lines.pop while lines.last.empty?

prev = false

lines.delete_if { |line|
  curr = line.empty?
  doit = prev && curr

  prev = curr
  doit
}

puts lines
