#! /usr/bin/env ruby

require 'nuggets/json/multi'
require 'nuggets/json/canonical'

if $0 == __FILE__
  if ARGV.include?('-h') || ARGV.include?('--help')
    abort "Usage: #{$0} [-h|--help] [-l|--lines] [-c|--canon] [SOURCE...]"
  end

  meth = ARGV.delete('--canon') || ARGV.delete('-c') ? :pc : :pp
  args = ARGV.delete('--lines') || ARGV.delete('-l') ? ARGF : [ARGF.read]

  args.each { |source| puts begin
    JSON.send(meth, source)
  rescue ParserError => err
    warn "#{err.class}: #{err}"
    source
  end }
end
