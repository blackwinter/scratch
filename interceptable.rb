#--
###############################################################################
#                                                                             #
# interceptable -- Mixin to intercept method calls on objects                 #
#                                                                             #
# Copyright (C) 2008 Jens Wille                                               #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@uni-koeln.de>                                    #
#                                                                             #
# interceptable is free software; you can redistribute it and/or modify it    #
# under the terms of the GNU General Public License as published by the Free  #
# Software Foundation; either version 3 of the License, or (at your option)   #
# any later version.                                                          #
#                                                                             #
# interceptable is distributed in the hope that it will be useful, but        #
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY  #
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License     #
# for more details.                                                           #
#                                                                             #
# You should have received a copy of the GNU General Public License along     #
# with interceptable. If not, see <http://www.gnu.org/licenses/>.             #
#                                                                             #
###############################################################################
#++

# See <http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/316382>
#
# This implementation uses Kernel#set_trace_func to invoke a callback on
# method calls.
#
# Unresolved issues: Search this file for "FIXME".

# First, we need to keep track of installed trace funcs.
module Kernel

  alias_method :_original_intercept_set_trace_func, :set_trace_func

  def set_trace_func(arg, stackable = false)
    $trace_funcs ||= []

    if arg
      set_trace_func(nil) unless stackable
      $trace_funcs << [arg, stackable]

      current_trace_funcs = $trace_funcs.map { |_arg, _| _arg }

      arg = lambda { |*args|
        current_trace_funcs.each { |trace_func| trace_func[*args] }
      }
    else
      if stackable
        $trace_funcs.clear
      else
        $trace_funcs.delete_if { |_, _stackable| !_stackable }
      end
    end

    _original_intercept_set_trace_func(arg)
  end

end

# Then, define a suitable trace func to intercept method calls.
module Interceptable

  def self.included(base)
    set_trace_func lambda { |event, file, line, method, binding, klass|
      if klass.equal?(base) && event =~ /call/ && method.to_s !~ /\A__/
        obj = eval('self', binding)

        if obj.respond_to?(:__intercept__, true)
          # FIXME: includes *any* local variables in the method, not just arguments!
          args  = eval('local_variables', binding).map { |arg| eval(arg, binding) }
          block = eval('Proc.new', binding) if eval('block_given?', binding)

          obj.send(:__intercept__, method, *args, &block)
        end

        # FIXME: prevent Ruby from calling the original method!!
        #raise Intercepted, method.to_s
      end
    }, true
  end

  private

  def __intercept__(method, *args)
    args.map! { |arg| arg.inspect }
    args << '&block' if block_given?

    warn "#{self}: #{self.class}##{method}(#{args.join(', ')})"
  end

  class Intercepted < StandardError; end

end

# Finally, provide a mixin to create blank slates.
module BlankSlate

  def self.included(base)
    base.send :include, Interceptable

    base.send(:define_method, :__intercept__) { |method, *args|
      warn "BlankSlate intercepting #{method} on #{self}"

      if block_given?
        __proxy_target__.__send__(method, *args) { |*a| yield(*a) }
      else
        __proxy_target__.__send__(method, *args)
      end
    }

    base.send(:private, :__intercept__)
  end

end

if $0 == __FILE__
  class A
    def foo; puts 'foo from A'; end
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
      warn "Intercepted #{method} on #{self}"
      yield method, *args if block_given?
    end
  end

  class D
    include BlankSlate

    def __proxy_target__
      @__proxy_target__ ||= A.new
    end

    def foo; puts 'foo from D'; end
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
  p D.new.class

  b = B.new
  b.foo
  def b.foo; puts "foo from #{self}"; end
  b.foo

  class B
    def bar; puts 'bar from B'; end
  end
  B.new.bar
  B.new.baz
end
