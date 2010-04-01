#! /usr/bin/ruby

require 'rexml/document'
require 'rexml/formatters/default'

xpaths = ARGV.empty? ? [nil] : ARGV

doc = REXML::Document.new(STDIN).root
fmt = REXML::Formatters::Default.new(false)
out = STDOUT

out.puts "<#{doc.name}>"

xpaths.each { |xpath|
  doc.elements.each(xpath) { |e|
    fmt.write(e, out)
    out.puts
  }
}

out.puts "</#{doc.name}>"
