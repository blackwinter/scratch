#--
###############################################################################
#                                                                             #
# codes -- Generate codes out of given digits                                 #
#                                                                             #
# Copyright (C) 2008 University of Cologne,                                   #
#                    Albertus-Magnus-Platz,                                   #
#                    50932 Cologne, Germany                                   #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@uni-koeln.de>                                    #
#                                                                             #
# codes is free software; you can redistribute it and/or modify it under the  #
# terms of the GNU General Public License as published by the Free Software   #
# Foundation; either version 3 of the License, or (at your option) any later  #
# version.                                                                    #
#                                                                             #
# codes is distributed in the hope that it will be useful, but WITHOUT ANY    #
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS   #
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more       #
# details.                                                                    #
#                                                                             #
# You should have received a copy of the GNU General Public License along     #
# with codes. If not, see <http://www.gnu.org/licenses/>.                     #
#                                                                             #
###############################################################################
#++

require 'set'

class Codes

  include Enumerable

  DIGITS = {
    :alpha_upper => ['A'..'Z'],
    :alpha_lower => ['a'..'z'],
    :alpha       => [:alpha_upper, :alpha_lower],

    :symbol      => %q{!"$%&/()=?.,:;-_#'+*<>},
    :sym         => :symbol,

    :binary      => [0..1],
    :bin         => :binary,

    :octal       => [0..7],
    :oct         => :octal,

    :decimal     => [0..9],
    :dec         => :decimal,

    :hex_upper   => [0..9, 'A'..'F'],
    :hex_lower   => [0..9, 'a'..'f'],
    :hexadecimal => :hex_upper,
    :hex         => :hexadecimal,

    :alnum_upper => [:decimal, :alpha_upper],
    :alnum_lower => [:decimal, :alpha_lower],
    :alnum       => [:alnum_upper, :alnum_lower],

    :all         => [:alnum, :symbol],
    :default     => :alnum_upper
  }

  def self.pw(length, digits = :all)
    new(length, digits).pick
  end

  attr_reader   :digits, :digits_size, :length, :bucket_length,
                :bucket_count, :bucket_size, :pool_size

  attr_accessor :position

  def initialize(length, digits = :default, options = {})
    @digits = digits_for(digits)
    @digits_size = @digits.size

    @length, @bucket_length = length
    @bucket_length ||= options[:bucket_length] || 0

    bucket_count = @digits_size ** @bucket_length
    if @bucket_count = options[:bucket_count]
      if bucket_count < @bucket_count
        raise "not enough bucket digits for bucket count #{@bucket_count}, " <<
              "only #{bucket_count} possible"
      end
    else
      @bucket_count = bucket_count
    end

    bucket_size = @digits_size ** @length
    if @bucket_size = options[:bucket_size]
      if bucket_size < @bucket_size
        raise "not enough digits for bucket size #{@bucket_size}, " <<
              "only #{bucket_size} possible"
      end
    else
      @bucket_size = bucket_size
    end

    # rcov hack :-(
    _ = [
      @digits_size ** (@length + @bucket_length),
      @bucket_count * @bucket_size
    ]
    @pool_size = _.min

    if pool_size = options[:pool_size]
      if @pool_size < pool_size
        raise "not enough digits for pool size #{pool_size}, " <<
              "only #{@pool_size} possible"
      end

      @pool_size, @possible_pool_size = pool_size, @pool_size
    end

    @randomize = options[:randomize]
    @digits = @digits.sort_by { rand } if @randomize

    @position = 0
  end

  def current_position
    @position - 1
  end

  def randomized?
    @randomize
  end

  def at(position)
    case position
      when Range, Array
        if block_given?
          position.each { |p| yield at(p) }
        else
          position.map { |p| at(p) }
        end
      when Integer
        if position < pool_size
          bucket_position, position = position.divmod(bucket_size)
          "#{build(bucket_position, bucket_length)}#{build(position, length)}"
        end
      else
        raise ArgumentError,
              "don't know how to handle position of type #{position.class}"
    end
  end

  alias_method :[], :at

  def bucket(position, size = bucket_size, random = false)
    case position
      when Range, Array
        if block_given?
          position.each { |p| bucket(p, size, random) { |*a| yield *a } }
        else
          position.map { |p| bucket(p, size, random) }
        end
      when Integer
        start = position * bucket_size

        if random
          set = Set.new

          while set.size < size
            set << at(start + rand(bucket_size))
          end

          block_given? ? yield(set.to_a) : set.to_a
        else
          range = start...start + size
          block_given? ? at(range) { |*a| yield *a } : at(range)
        end
      else
        raise ArgumentError,
              "don't know how to handle position of type #{position.class}"
    end
  end

  def pick(count = nil)
    if block_given?
      (count || 1).times { yield pick }
    else
      if count
        (0...count).map { pick }
      else
        at(rand(pool_size - 1))
      end
    end
  end

  def scoop(count = nil, size = bucket_size, random = false)
    if block_given?
      (count || 1).times { yield scoop(nil, size, random) }
    else
      if count
        (0...count).map { scoop(nil, size, random) }
      else
        bucket(rand(bucket_count), size, random)
      end
    end
  end

  def each
    while code = self.next
      yield code
    end
  end

  def next
    code = at(@position)
    code ? @position += 1 : reset
    code
  end

  def reset
    @position = 0
  end

  private

  def digits_for(digits)
    case digits
      when Range
        digits.to_a
      when Array
        digits.map { |item| digits_for(item) }.flatten.uniq
      when Symbol
        digits_for(DIGITS[digits])
      when String
        digits.split(//)
      else
        raise ArgumentError,
              "don't know how to handle digits of type #{digits.class}"
    end.map { |digit| digit.to_s }.sort
  end

  def build(position, length)
    if length > 0
      code = ''

      begin
        code << digits[position % digits_size]
      end until (position /= digits_size).zero?

      while code.length < length
        code << digits[0]
      end

      code[0, length].reverse
    end
  end

end

# {{{ SPECS
if $0 == __FILE__ || %w[spec rcov].include?(File.basename($0))
  require 'rubygems'
  require 'spec'

  rspec_options.colour = true

  # FIXME: better way to spec codes than just by means of their length
  describe Codes do

    it 'should generate passwords with default digits' do
      Codes.pw(8).length.should == 8
    end

    it 'should generate passwords with custom digits' do
      Codes.pw(8, [:alnum, '-_#']).length.should == 8
    end

    it 'should take different length arguments (1)' do
      codes = Codes.new(6)
      codes.length.should == 6
      codes.bucket_length.should == 0
    end

    it 'should take different length arguments (2)' do
      codes = Codes.new([6, 2])
      codes.length.should == 6
      codes.bucket_length.should == 2
    end

    it 'should take different length arguments (3)' do
      codes = Codes.new(6, :default, :bucket_length => 2)
      codes.length.should == 6
      codes.bucket_length.should == 2
    end

    it 'should take different length arguments (4)' do
      codes = Codes.new([6, 2], :default, :bucket_length => 4)
      codes.length.should == 6
      codes.bucket_length.should == 2
    end

    it 'should have default digits' do
      codes = Codes.new(6)
      codes.digits.should_not be_empty
      codes.digits_size.should_not be_zero
    end

    it 'should take custom digits as argument' do
      codes = Codes.new(6, 0..3)
      codes.digits.should_not be_empty
      codes.digits_size.should == 4
    end

    it 'should raise an error when provided with invalid digits (1)' do
      lambda {
        Codes.new(6, :foo)
      }.should raise_error(ArgumentError)
    end

    it 'should raise an error when provided with invalid digits (2)' do
      lambda {
        Codes.new(6, 123)
      }.should raise_error(ArgumentError)
    end

    it 'should take various options (1)' do
      codes = Codes.new(6, :default, :bucket_length => 4)
      codes.bucket_length.should == 4
    end

    it 'should take various options (2)' do
      codes = Codes.new([6, 2], :default, :bucket_size => 100)
      codes.bucket_size.should == 100
    end

    it 'should take various options (3)' do
      codes = Codes.new([6, 2], :default, :pool_size => 1000)
      codes.pool_size.should == 1000
      codes.instance_variable_get(:@possible_pool_size).should_not be_nil
    end

    it 'should take various options (4)' do
      codes = Codes.new([6, 2], :default, :randomize => true)
      codes.should be_randomized
    end

    it 'should perform sanity checks on arguments (1)' do
      lambda {
        Codes.new([6, 2], 0..3, :bucket_count => 4 ** 2 + 1)
      }.should raise_error(RuntimeError)
    end

    it 'should perform sanity checks on arguments (2)' do
      lambda {
        Codes.new([6, 2], 0..3, :bucket_size => 4 ** 6 + 1)
      }.should raise_error(RuntimeError)
    end

    it 'should perform sanity checks on arguments (3)' do
      lambda {
        Codes.new([6, 2], 0..3, :pool_size => 4 ** 8 + 1)
      }.should raise_error(RuntimeError)
    end

    it 'should perform sanity checks on arguments (4)' do
      lambda {
        Codes.new([6, 2], 0..3, :bucket_count => 4,
                                :bucket_size  => 10,
                                :pool_size    => 4 * 10 + 1)
      }.should raise_error(RuntimeError)
    end

    it 'should give access to a certain code by position' do
      code = Codes.new([6, 2]).at(1234)
      code.should be_an_instance_of(String)
      code.length.should == 6 + 2
    end

    it 'should provide a convenience method for accessing codes by position' do
      codes = Codes.new([6, 2])
      code = codes[1234]
      code.should be_an_instance_of(String)
      code.length.should == 6 + 2
      code.should == codes.at(1234)
    end

    it 'should give access to codes by a range of positions (1)' do
      codes = Codes.new([6, 2]).at(1234..1245)
      codes.size.should == 12
      codes.each { |code|
        code.should be_an_instance_of(String)
        code.length.should == 6 + 2
      }
    end

    it 'should give access to codes by a range of positions (2)' do
      codes = []
      Codes.new([6, 2]).at(1234..1245) { |code| codes << code }
      codes.size.should == 12
      codes.each { |code|
        code.should be_an_instance_of(String)
        code.length.should == 6 + 2
      }
    end

    it 'should give access to codes by an array of positions' do
      codes = Codes.new([6, 2]).at([1234, 1245])
      codes.length.should == 2
      codes.each { |code|
        code.should be_an_instance_of(String)
        code.length.should == 6 + 2
      }
    end

    it 'should raise an error when accessed by an invalid position (1)' do
      lambda {
        Codes.new([6, 2]).at(:foo)
      }.should raise_error(ArgumentError)
    end

    it 'should raise an error when accessed by an invalid position (2)' do
      lambda {
        Codes.new([6, 2]).at(nil)
      }.should raise_error(ArgumentError)
    end

    it 'should return nil when accessed at too large a position' do
      codes = Codes.new([2, 2])
      codes.at(codes.pool_size + 1).should be_nil
    end

    it 'should give access to buckets of codes by bucket position (1)' do
      codes = Codes.new([2, 2])
      bucket = codes.bucket(6)
      bucket.size.should == codes.bucket_size
    end

    it 'should give access to buckets of codes by bucket position (2)' do
      codes = Codes.new([2, 2])
      bucket = codes.bucket(6, 100)
      bucket.size.should == 100
    end

    it 'should give access to buckets of codes by bucket position (3)' do
      codes = Codes.new([2, 2])
      bucket = codes.bucket(6, 100, true)
      bucket.size.should == 100
    end

    it 'should give access to buckets of codes by a range of bucket positions (1)' do
      buckets = []
      Codes.new([6, 2]).bucket(0...6, 100, true) { |bucket| buckets << bucket }
      buckets.size.should == 6
      buckets.each { |bucket| bucket.size.should == 100 }
    end

    it 'should give access to buckets of codes by a range of bucket positions (2)' do
      buckets = Codes.new([6, 2]).bucket(0...6, 100, true)
      buckets.size.should == 6
      buckets.each { |bucket| bucket.size.should == 100 }
    end

    it 'should give access to buckets of codes by an array of bucket positions' do
      buckets = []
      Codes.new([6, 2]).bucket([0, 6], 100, true) { |bucket| buckets << bucket }
      buckets.size.should == 2
      buckets.each { |bucket| bucket.size.should == 100 }
    end

    it 'should raise an error when accessed by an invalid bucket position (1)' do
      lambda {
        Codes.new([6, 2]).bucket(:foo)
      }.should raise_error(ArgumentError)
    end

    it 'should raise an error when accessed by an invalid bucket position (2)' do
      lambda {
        Codes.new([6, 2]).bucket(nil)
      }.should raise_error(ArgumentError)
    end

    it 'should pick a single code (1)' do
      code = Codes.new([6, 2]).pick
      code.should be_an_instance_of(String)
      code.length.should == 6 + 2
    end

    it 'should pick a single code (2)' do
      code = nil
      Codes.new([6, 2]).pick { |code| }
      code.should be_an_instance_of(String)
      code.length.should == 6 + 2
    end

    it 'should pick several codes' do
      codes = Codes.new([6, 2]).pick(10)
      codes.size.should == 10
      codes.each { |code|
        code.should be_an_instance_of(String)
        code.length.should == 6 + 2
      }
    end

    it 'should scoop a number of buckets (1)' do
      codes = Codes.new([2, 2])
      codes.scoop(6) { |bucket|
        bucket.size.should == codes.bucket_size
      }.should == 6
    end

    it 'should scoop a number of buckets (2)' do
      Codes.new([2, 2]).scoop(6, 100) { |bucket|
        bucket.size.should == 100
      }.should == 6
    end

    it 'should scoop a number of buckets (3)' do
      buckets = Codes.new([2, 2]).scoop(6, 100)
      buckets.size.should == 6
      buckets.each { |bucket|
        bucket.size.should == 100
      }
    end

    it 'should scoop a number of buckets (4)' do
      buckets = Codes.new([2, 2]).scoop(6, 100, true)
      buckets.size.should == 6
      buckets.each { |bucket|
        bucket.size.should == 100
      }
    end

    it 'should be enumerable (1)' do
      codes = Codes.new([2, 2])
      codes.should respond_to(:map)
      codes.should respond_to(:to_a)
    end

    it 'should be enumerable (2)' do
      codes = Codes.new([2, 2], 0..3)
      codes.to_a.size.should == codes.pool_size
    end

    it 'should tell the current position' do
      codes = Codes.new([2, 2])
      i = 0
      codes.each { break if (i += 1) > 1234 }
      codes.current_position.should == 1234
    end

  end
end
# }}}

# vi:foldmethod=marker
