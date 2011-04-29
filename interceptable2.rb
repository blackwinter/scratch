#--
###############################################################################
#                                                                             #
# interceptable -- Mixin to intercept method calls on objects                 #
#                                                                             #
# Copyright (C) 2008-2011 Jens Wille                                          #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@uni-koeln.de>                                    #
#                                                                             #
# interceptable is free software; you can redistribute it and/or modify it    #
# under the terms of the GNU Affero General Public License as published by    #
# the Free Software Foundation; either version 3 of the License, or (at your  #
# option) any later version.                                                  #
#                                                                             #
# interceptable is distributed in the hope that it will be useful, but        #
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY  #
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public      #
# License for more details.                                                   #
#                                                                             #
# You should have received a copy of the GNU Affero General Public License    #
# along with interceptable. If not, see <http://www.gnu.org/licenses/>.       #
#                                                                             #
###############################################################################
#++

# See <http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/316382>
#
# This implementation uses the method_added hook to replace methods with their
# intercepted counterpart. The original one is aliased appropriately.
#
# Unresolved issues:
#
# - method_added isn't triggered by methods added through inheritance
# - only works for actually defined methods -- pretty useless for BlankSlate

module Interceptable

  PREFIX = '_original_intercept_'.freeze

  SKIP_RE = %r{\A__|\A#{PREFIX}}o.freeze

  def self.included(base)
    class << base; self; end.send(:define_method, :method_added) { |method|
      unless method.to_s =~ SKIP_RE
        original = Interceptable.method_before_intercept(method)

        unless method_defined?(original)
          alias_method original, method

          # DAMMIT! define_method doesn't accept block param before 1.9 :-(
          class_eval <<-EOT, __FILE__, __LINE__
            def #{method}(*args)
              if block_given?
                __intercept__(#{method.inspect}, *args) { |*a| yield(*a) }
              else
                __intercept__(#{method.inspect}, *args)
              end
            end
          EOT
        end
      end
    }
  end

  private

  def self.method_before_intercept(method)
    "#{PREFIX}#{method}"
  end

  def method_before_intercept(method)
    Interceptable.method_before_intercept(method)
  end

  def __intercept__(method, *args)
    args.map! { |arg| arg.inspect }
    args << '&block' if block_given?

    warn "#{self}: #{self.class}##{method}(#{args.join(', ')})" <<
         " [original is at #{method_before_intercept(method)}]"
  end

end

module BlankSlate

  def self.included(base)
    base.send :include, Interceptable

    base.class_eval <<-EOT, __FILE__, __LINE__
      def __intercept__(method, *args)
        warn "BlankSlate intercepting \#{method} on \#{self}"

        if block_given?
          __proxy_target__.__send__(method, *args) { |*a| yield(*a) }
        else
          __proxy_target__.__send__(method, *args)
        end
      end
    EOT

    base.send(:private, :__intercept__)
  end

end

if $0 == __FILE__
  class A
    def foo; puts 'foo from A'; end

    def bar; yield 'bar from A'; end
  end

  class B
    include Interceptable

    def foo; puts 'foo from B'; end
  end

  class C
    include Interceptable

    def foo; puts 'foo from C'; end

    def bar(*a); puts "bar from C (#{a.inspect})"; end

    def baz(a, b = nil); c = :c; puts "baz from C (#{[a, b, c].inspect})"; end

    private

    def __intercept__(method, *args)
      warn "Intercepted #{method} on #{self} (use: #{method_before_intercept(method)})"
      yield method, *args if block_given?
    end
  end

  class D
    include BlankSlate

    def __proxy_target__
      @__proxy_target__ ||= A.new
    end

    def foo; puts 'foo from D'; end
    def bar; end  # FIXME: shouldn't be necessary
  end

  A.new.foo
  B.new.foo
  B.new.foo { |*a| p a }
  C.new.foo
  C.new.foo { |*a| p a }
  C.new.bar(1, 2, 3)
  C.new.bar(1, 2, 3) { |*a| p a }
  C.new.baz(:a)
  C.new.baz(:a, :b)
  C.new.baz(:a)     { |*a| p a }
  C.new.baz(:a, :b) { |*a| p a }
  D.new.foo
  D.new.bar { |*a| p a }
  p D.new.class  # FIXME: should be A

  b = B.new
  b.foo
  def b.foo; puts "foo from #{self}"; end
  b.foo

  class B
    def bar; puts 'bar from B'; end
  end
  B.new.bar

  class E < A
    include Interceptable

    def bar; puts 'bar from E'; end
  end
  E.new.foo  # FIXME: should be intercepted
  E.new.bar
end
