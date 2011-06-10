#! /usr/bin/ruby

#--
###############################################################################
#                                                                             #
# xmluniq -- Filter duplicate records from XML                                #
#                                                                             #
# Copyright (C) 2011 Jens Wille                                               #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@uni-koeln.de>                                    #
#                                                                             #
# xmluniq is free software; you can redistribute it and/or modify it under    #
# the terms of the GNU Affero General Public License as published by the Free #
# Software Foundation; either version 3 of the License, or (at your option)   #
# any later version.                                                          #
#                                                                             #
# xmluniq is distributed in the hope that it will be useful, but WITHOUT ANY  #
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS   #
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for     #
# more details.                                                               #
#                                                                             #
# You should have received a copy of the GNU Affero General Public License    #
# along with xmluniq. If not, see <http://www.gnu.org/licenses/>.             #
#                                                                             #
###############################################################################
#++

require 'optparse'
require 'tempfile'
require 'erb'

# == Comparison with <tt>uniq(1)</tt>
#
# XmlUniq recognizes duplicate records across whole file (not only consecutive
# ones) and interprets the <tt>--repeated</tt> option differently.
#
# <tt>uniq(1)</tt> (+U+) vs. XmlUniq (+X+):
#
#                  | a a a b b c b b a
#   ----------------------------------
#   (default)      | U     U   U U   U
#                  | X     X   X
#   ----------------------------------
#   --repeated     | U     U     U
#                  |   X X   X   X X X
#   ----------------------------------
#   --all-repeated | U U U U U   U U
#                  | X X X X X   X X X
#   ----------------------------------
#   --unique       |           U     U
#                  |           X
#
#
# == Processors
#
# XmlUniq can make use of different XSLT processors to achieve its goals.
# Currently supported and tried in this order are:
#
# +libxslt+::  Requires the {libxslt bindings}[https://github.com/xml4r/libxslt-ruby].
# +xsltproc+:: Requires the {xsltproc program}[http://xmlsoft.org/xslt/xsltproc2.html].
#
#
# === Note
#
# Node comparison is based on xsl:key[http://www.w3.org/TR/xslt#function-key],
# which converts the key value (specified by the <tt>--key</tt> option) to a
# string[http://www.w3.org/TR/xpath#function-string]. When the key happens to
# be a node (which is the default setting), its string value includes only the
# text (and whitespace) from its child nodes; neither attributes nor tag names
# are taken into account.
#
# To remedy this, the +libxslt+ processor registers an extension function that
# returns a node's *full* string representation if the bindings support the
# registration of such extension functions. The +xsltproc+ processor, however,
# does not support this extension at all.
#
#
# == TODO
#
# - namespaces?
# - encoding detection?
# - cdata-section-elements?
# - preserve original XML declaration?

module XmlUniq

  extend self

  NAME     = File.basename($0, '.rb')

  VERSION  = '0.0.2'

  USAGE    = "Usage: #{$0} [-h|--help] [options] [<file>]"

  DEFAULTS = {
    :path          => '/*/*',
    :key           => '.',
    :last          => false,
    :dup           => false,
    :all           => false,
    :only_records  => false,
    :only_matching => false,
    :encoding      => 'UTF-8',
    :input         => '-',
    :output        => '-',
    :indent        => false,
    :strip_space   => false,
    :print_xslt    => false,
    :print_cmd     => false,
    :dry_run       => false
  }

  NAMESPACE_URI = "http://#{NAME}.ext"

  def run(xslt, argv = ARGV)
    options = parse_options(argv)

    xslt = ERB.new(xslt).result(binding).strip
    warn xslt if options[:print_xslt]

    if respond_to?(runner = "run_#{processor}", true)
      send(runner, xslt, options)
    elsif processor
      abort "Don't know how to run processor: #{processor}"
    else
      abort 'No processor to run!'
    end
  end

  private

  def processor
    defined?(@processor) ? @processor : @processor =
      have_libxslt? ? :libxslt : have_xsltproc? ? :xsltproc : nil
  end

  def have_libxslt?
    defined?(@have_libxslt) ? @have_libxslt : @have_libxslt = begin
      begin
        require 'rubygems'
        gem 'blackwinter-libxslt'
      rescue LoadError
      end

      require 'libxslt'
      true
    rescue LoadError
      false
    end
  end

  def have_libxslt_register?
    defined?(@have_libxslt_register) ? @have_libxslt_register : @have_libxslt_register =
      have_libxslt? && LibXSLT::XSLT.respond_to?(:register)
  end

  def have_xsltproc?
    defined?(@have_xsltproc) ? @have_xsltproc : @have_xsltproc =
      !%x{which xsltproc}.empty?
  end

  def run_libxslt(xslt, options)
    args = options[:input] == '-' ? [:io, STDIN] : [:file, options[:input]]

    encoding = begin
      LibXML::XML::Encoding.const_get(options[:encoding].upcase.tr('-', '_'))
    rescue NameError
      warn "Unsupported encoding: #{options[:encoding]}. Defaulting to UTF-8."
      LibXML::XML::Encoding::UTF_8
    end

    LibXSLT::XSLT.register(NAMESPACE_URI, 'node-string') { |args|
      args.join('|')
    } if have_libxslt_register?

    unless options[:dry_run]
      # LibXSLT::XSLT::Stylesheet expects top-level constant XML (old libxml-ruby interface)
      Object.const_set(:XML, LibXML::XML) unless Object.const_defined?(:XML) || have_libxslt_register?

      xml = LibXSLT::XSLT::Stylesheet.new(
        LibXML::XML::Document.string(xslt)
      ).apply(LibXML::XML::Document.send(
        *args << { :encoding => encoding }
      ))

      options[:output] == '-' ? STDOUT.write(xml) :
      File.open(options[:output], 'w') { |out| out.write(xml) }
    end
  end

  def run_xsltproc(xslt, options)
    cmd = [processor.to_s,
      '--output',      options[:output],
      '--encoding',    options[:encoding],
      xslt_file(xslt), options[:input]
    ]

    warn cmd.join(' ') if options[:print_cmd]
    system(*cmd) or abort "Could not execute command: #{cmd.join(' ')}" unless options[:dry_run]
  end

  def xslt_file(xslt)
    tempfile = Tempfile.new([NAME, '.xslt'])
    tempfile.write(xslt)
    tempfile.path
  ensure
    tempfile.close if tempfile
  end

  def parse_options(arguments, options = DEFAULTS)
    option_parser(options).parse!(arguments)

    input = arguments.shift
    options[:input] = input if input

    abort USAGE unless arguments.empty?

    options
  end

  def option_parser(options)
    OptionParser.new { |opts|
      opts.banner = USAGE

      opts.separator ''
      opts.separator 'Options:'

      opts.on('-p', '--path XPATH', 'Use XPATH to determine what constitutes', "a record [Default: '#{options[:path]}']") { |xpath|
        options[:path] = xpath
      }

      opts.on('-k', '--key XPATH', 'Use XPATH to determine the part of', "a record to compare on [Default: '#{options[:key]}']") { |xpath|
        options[:key] = xpath
      }

      opts.separator ''

      opts.on('-l', '--[no-]last', 'Keep last, not first, in a series', "of duplicate records [Default: #{options[:last]}]") { |last|
        options[:last] = last
      }

      opts.separator ''

      opts.on('-d', '--repeated', 'Only print duplicate records') {
        options[:dup] = true
        options[:all] = false
      }

      opts.on('-D', '--all-repeated', 'Print all duplicate records') {
        options[:dup] = true
        options[:all] = true
      }

      opts.on('-u', '--unique', 'Only print unique records') {
        options[:dup] = false
        options[:all] = true
      }

      opts.separator ''

      opts.on('-r', '--only-records', 'Only print elements matching PATH (records)') {
        options[:only_records] = true
      }

      opts.on('-m', '--only-matching', 'Only print records matching PATH[KEY]') {
        options[:only_matching] = true
      }

      opts.separator ''
      opts.separator 'Input options:'

      opts.on('-e', '--encoding ENCODING', "The encoding of the input [Default: '#{options[:encoding]}']") { |encoding|
        options[:encoding] = encoding
      }

      opts.separator ''
      opts.separator 'Output options:'

      opts.on('-o', '--output FILE', 'Write output to FILE instead of STDOUT') { |file|
        options[:output] = file
      }

      opts.separator ''

      opts.on('-i', '--[no-]indent', "Indent the result tree nicely [Default: #{options[:indent]}]") { |indent|
        options[:indent] = indent
      }

      opts.on('-w', '--[no-]strip-space', "Strip whitespace from the tree [Default: #{options[:strip_space]}]", 'NOTE: This option may also affect the way', 'records are compared!') { |strip_space|
        options[:strip_space] = strip_space
      }

      opts.separator ''
      opts.separator 'Debug options:'

      opts.on('-X', '--print-xslt', 'Print the generated XSLT stylesheet on STDERR') {
        options[:print_xslt] = true
      }

      opts.on('-C', '--print-cmd', 'Print the executed command on STDERR') {
        options[:print_cmd] = true
      } if processor == :xsltproc

      opts.separator ''

      opts.on('-N', '--dry-run', "Don't run the actual transformation, just print", 'debug information (if any)') {
        options[:dry_run] = true
      }

      opts.separator ''
      opts.separator 'Generic options:'

      opts.on('-h', '--help', 'Print this help message and exit') {
        abort opts.to_s
      }

      opts.on('--version', 'Print program version and exit') {
        abort "#{NAME} v#{XmlUniq::VERSION}"
      }
    }
  end

end

XmlUniq.run(DATA.read) if $0 == __FILE__

__END__
<%
  order = %w[keep drop]
  order.reverse! if options[:dup]

  use = options[:key]
  use = "ext:node-string(#{use})" if have_libxslt_register?

  key     = "key('key', #{use})"
  match   = "#{options[:path]}[#{options[:key]}]"
  pattern = options[:all] ? "#{key}[2]" : "generate-id() != generate-id(#{key}[#{options[:last] ? 'last()' : '1'}])"
%>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"<%= %Q{ xmlns:ext="#{NAMESPACE_URI}"} if have_libxslt_register? %>>
  <!-- <%= NAME %> v<%= VERSION %> [<%= processor %>] / <%= options.map { |k, v| "#{k}=#{v.inspect}" if v }.compact.sort.join(', ') %> -->

  <!-- set output options -->
  <xsl:output indent="<%= options[:indent] ? 'yes' : 'no' %>" encoding="<%= options[:encoding] %>" />

  <!-- configure whitespace stripping -->
  <% if options[:strip_space] %><xsl:strip-space elements="*" /><% else %><!-- (default) --><% end %>

  <!-- define key for record comparison -->
  <xsl:key name="key" match="<%= match %>" use="<%= use %>" />

  <!-- define named templates -->
  <xsl:template name="keep"><xsl:copy-of select="." /></xsl:template>
  <xsl:template name="drop" />

  <!-- preserve processing instructions and comments -->
  <xsl:template match="processing-instruction()|comment()">
    <xsl:call-template name="keep" />
  </xsl:template>

  <!-- identity transform -->
  <xsl:template match="*">
    <xsl:copy>
      <xsl:apply-templates mode="uniq" />
    </xsl:copy>
  </xsl:template>

  <!-- handle non-record elements -->
  <xsl:template priority="0" mode="uniq" match="*">
    <xsl:call-template name="<%= options[:only_records] ? 'drop' : 'keep' %>" />
  </xsl:template>

  <!-- handle non-matching records -->
  <xsl:template priority="1" mode="uniq" match="<%= options[:path] %>">
    <xsl:call-template name="<%= options[:only_matching] ? 'drop' : 'keep' %>" />
  </xsl:template>

  <!-- handle unique records -->
  <xsl:template priority="2" mode="uniq" match="<%= match %>">
    <xsl:call-template name="<%= order.first %>" />
  </xsl:template>

  <!-- handle duplicate records -->
  <xsl:template priority="3" mode="uniq" match="<%= match %>[<%= pattern %>]">
    <xsl:call-template name="<%= order.last %>" />
  </xsl:template>
</xsl:stylesheet>
