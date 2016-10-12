#! /usr/bin/env ruby

require 'csv'
require 'optparse'

class CSVSort

  VERSION = '0.1'

  MAXCOLS = ENV.fetch('CSVSORT_MAXCOLS', 16).to_i

  DEFAULT_OPTIONS = {
    numeric_sort:    false,
    reverse:         false,
    key:             nil,
    input:           $stdin,
    output:          $stdout,
    field_separator: CSV::DEFAULT_OPTIONS[:col_sep],
    quote_char:      CSV::DEFAULT_OPTIONS[:quote_char],
    with_header:     false
  }

  ORDERING = { n: :numeric_sort, r: :reverse }

  KEYDEF = /\A(\d+)([#{ORDERING.keys.join}]*)\z/o

  PRESENT = [0].freeze

  MISSING = [1].freeze

  class << self

    def run(argv = ARGV, prog = $0)
      new(parse_options(argv, prog)).run
    end

    def parse_options(argv, prog, options = {})
      usage = "Usage: #{prog} [-h|--help] [options] [FILE]"

      OptionParser.new { |opts|
        opts.banner = usage

        opts.separator ' '
        opts.separator 'Ordering options:'

        opts.on('-n', '--numeric-sort', 'Compare according to string numerical value') {
          options[:numeric_sort] = true
        }

        opts.on('-r', '--reverse', 'Reverse the result of comparisons') {
          options[:reverse] = true
        }

        opts.separator ' '
        opts.separator 'Other options:'

        opts.on('-k', '--key=KEYDEF', 'Sort via a key; KEYDEF gives location and type') { |k|
          options[:key] = k.split(',').map { |j|
            j =~ KEYDEF ? [$1.to_i - 1, $2] : raise(OptionParser::InvalidArgument, k) }.to_h
        }

        opts.on('-o', '--output=FILE', 'Write result to FILE instead of standard output') { |o|
          options[:output] = File.open(o, 'w')
        }

        opts.on('-t', '--field-separator=SEP', "Use SEP instead of `#{DEFAULT_OPTIONS[:field_separator]}' as field separator") { |t|
          options[:field_separator] = t
        }

        opts.on('-Q', '--quote-char=CHR', "Use CHR instead of `#{DEFAULT_OPTIONS[:quote_char]}' as quote character") { |q|
          options[:quote_char] = q
        }

        opts.on('-H', '--with-header', 'Preserve header line when sorting') {
          options[:with_header] = true
        }

        opts.separator ' '
        opts.separator 'Generic options:'

        opts.on('-h', '--help', 'Display this help and exit') {
          warn opts
          exit
        }

        opts.on('--version', 'Output version information and exit') {
          warn "#{File.basename(prog, '.rb')} v#{VERSION}"
          exit
        }

        opts.separator ' '
        opts.separator <<-EOT
KEYDEF is F[OPTS][,F[OPTS]]..., where F is a field number (origin 1).
OPTS is one or more single-letter ordering options [#{ORDERING.keys.join}], which override
global ordering options for that key. If no key is given, use the entire
line as the key.
        EOT

        opts.separator ' '
        opts.separator 'With no FILE, or when FILE is -, read standard input.'
      }.parse!(argv)

      file = argv.shift
      abort usage unless argv.empty?

      options[:input] = File.open(file) if file && file != '-'

      options
    end

  end

  def initialize(options = {})
    @options = DEFAULT_OPTIONS.merge(options)

    augment_input
    augment_key
  end

  attr_reader :options

  def run(res = Hash.new { |h, k| h[k] = [] })
    skip_header(*(i, o = options.values_at(:input, :output)))
    extend(i.is_a?(GetsLine) ? LineInput : SeekInput)
    sort(res, o, &read(i, &blk(csv(i), res)))
  end

  private

  def skip_header(input, output, skip = options[:with_header])
    output.puts input.gets if skip
  end

  def sort(res, output)
    res.sort.each { |_, v| v.each { |w| output.puts yield(w) } }
  end

  def csv(input, f = options[:field_separator], q = options[:quote_char])
    CSV.new(input, col_sep: f, quote_char: q)
  end

  def blk(csv, res, key = options[:key])
    lambda { |b| csv.each { |row|
      k = key(key, row); b[lambda { |v| res[k] << v }] } }
  end

  def key(key, row)
    key.map { |i, j| val(row[i], *j.values_at(*ORDERING.keys)) }
  end

  def val(val, num, rev)
    val.nil? ? MISSING : begin key = PRESENT.dup
      num ? key << num(val) : key.concat(val.codepoints)
      rev ? key.map! { |v| -v } : key
    end
  end

  def num(val)
    val.to_f
  end

  def augment_input(input = options[:input])
    input.pos
  rescue NoMethodError, Errno::ESPIPE => e
    options[:input] = input.dup.extend(GetsLine)
  end

  def augment_key(key = options[:key])
    options[:key] = opt = Hash.new { |h, k| h[k] = {} }

    (key || Array.new(MAXCOLS) { |i| i }).each { |k, v|
      v, w = v.to_s, opt[k]

      ORDERING.each { |i, j| w[i] = v.include?(i.to_s) || options[j] }
    }
  end

  module GetsLine

    def gets(*)
      @line = super
    end

    def line
      @line
    end

  end

  module SeekInput

    def read(input, pos = input.pos)
      yield lambda { |add| add[pos]; pos = input.pos }
      lambda { |pos| input.seek(pos); input.gets }
    end

  end

  module LineInput

    def read(input)
      yield lambda { |add| add[input.line] }
      lambda { |line| line }
    end

  end

end

if $0 == __FILE__ then CSVSort.run
elsif File.basename($0) == 'rspec' &&
  ARGV.any? { |i| File.expand_path(i) == __FILE__ }

  describe CSVSort, '#run' do

    def self.sort(description, input, expected, options = {})
      describe(description) { [true, false].each { |seekable|
        subject { described_class.new(options.merge(input: io, output: out)) }

        let(:out) { StringIO.new('') }

        let(:res) { subject.run }

        describe("#{'non-' unless seekable}seekable") {
          let(:io) { seekable ? StringIO.new(input) : Class.new {
            def initialize(input); @lines = input.lines; end
            def gets(*); @lines.shift; end
          }.new(input) }

          it('should return an Array') {
            expect(res).to be_an(Array)
          }

          it('should have the expected number of items') {
            len = input.lines.size
            len -= 1 if subject.options[:with_header]

            expect(res.size).to eq(len)
          }

          it('should give the expected result') {
            res
            expect(out.string).to eq(expected)
          }
        } }
      }
    end

    sort 'empty', '', ''

    describe 'numbers' do

      describe 'simple' do

        input = <<-EOT
1,2,3
3,2,1
1,2,1
        EOT

        sort 'lexical', input, <<-EOT
1,2,1
1,2,3
3,2,1
        EOT

        sort 'numeric', input, <<-EOT, numeric_sort: true
1,2,1
1,2,3
3,2,1
        EOT

      end

      describe 'advanced' do

        input = <<-EOT
1,2,3
3,2,1
10,12,1
        EOT

        sort 'lexical', input, <<-EOT
1,2,3
10,12,1
3,2,1
        EOT

        sort 'numeric', input, <<-EOT, numeric_sort: true
1,2,3
3,2,1
10,12,1
        EOT

      end

    end

    sort 'complex', <<-EOT1, <<-EOT2, key: { 2 => :nr, 3 => :n, 0 => nil }, with_header: true, field_separator: ';'
a;b;c;d
foo;x;2;1.25
bar;y;;100
baz;z;2;1.25
"quix;quax";x;1;1.4
"quax""quix";x;1;
quux quox;y;10;-2.5
quox-quux;y;10;2.5
    EOT1
a;b;c;d
quux quox;y;10;-2.5
quox-quux;y;10;2.5
baz;z;2;1.25
foo;x;2;1.25
"quix;quax";x;1;1.4
"quax""quix";x;1;
bar;y;;100
    EOT2

  end

end
