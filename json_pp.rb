#! /usr/bin/env ruby

require 'json'

module JSON

  class PP_KEY < String

    def eql?(*)
      false
    end

  end

  class PP_OBJECT < Hash

    def []=(k, v)
      super(PP_KEY.new(k), v)
    end

  end

  def self.pp(source, opt = {})
    pretty_generate(parse(source, opt.merge(object_class: PP_OBJECT)))
  rescue ParserError => err
    warn "#{err.class}: #{err}"
    source
  end

end

if $0 == __FILE__
  if ARGV.include?('-h') || ARGV.include?('--help')
    abort "Usage: #{$0} [-h|--help] [-l|--lines] [SOURCE...]"
  end

  args = ARGV.delete('--lines') || ARGV.delete('-l') ? ARGF : [ARGF.read]
  args.each { |source| puts JSON.pp(source) }
end
