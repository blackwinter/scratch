#! /usr/bin/env ruby

require 'json'

module JSON

  K = Class.new(String) { def eql?(*) false end }
  O = Class.new(Hash) { def []=(k, v) super(K.new(k), v) end }

  def self.pp(source, opt = {})
    pretty_generate(parse(source, opt.merge(object_class: O)))
  end

end

puts JSON.pp(ARGF.read) if $0 == __FILE__
