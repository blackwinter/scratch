#! /usr/bin/env ruby

require 'json'

module JSON

  extend self

  PP_OPT = :_json_pp_canonical

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

  def pp(source, opt = {})
    obj = parse(source, opt.merge(object_class: PP_OBJECT))
    pretty_generate(opt[PP_OPT] ? send(PP_OPT, obj) : obj)
  rescue ParserError => err
    warn "#{err.class}: #{err}"
    source
  end

  def pc(source, opt = {})
    pp(source, opt.merge(PP_OPT => true))
  end

  private

  def _json_pp_canonical(obj)
    case obj
      when Hash
        obj.class.new.tap { |res|
          obj.keys.sort.each { |k| res[k] = send(PP_OPT, obj[k]) } }
      when Array
        obj.map { |v| send(PP_OPT, v) }.sort_by(&:to_s)
      else
        obj
    end
  end

end

if $0 == __FILE__
  if ARGV.include?('-h') || ARGV.include?('--help')
    abort "Usage: #{$0} [-h|--help] [-l|--lines] [-c|--canon] [SOURCE...]"
  end

  meth = ARGV.delete('--canon') || ARGV.delete('-c') ? :pc : :pp
  args = ARGV.delete('--lines') || ARGV.delete('-l') ? ARGF : [ARGF.read]

  args.each { |source| puts JSON.send(meth, source) }
end
