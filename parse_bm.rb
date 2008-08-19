#! /usr/bin/ruby

require 'rubygems'
require 'hpricot'

class String
  def to_time; Time.at(to_i) end
end

class NilClass
  def to_time; self end
end

class Time
  def to_s; to_i.to_s end
end

class Bookmarks

  def self.sync(infile1, infile2, outfile = infile1)
    new(infile1).sync(new(infile2)).write(outfile)
  end

  def self.new(file)
    case input = File.read(file)
      when %r{\A<!DOCTYPE NETSCAPE-Bookmark-file-1>}
        Netscape.new(input)
      else
        raise "unknown bookmarks file type: #{file}"
    end
  end

  class Base

    def sync(bm)
      last_modified < bm.last_modified ? bm : self
    end

  end

  class Netscape < Base

    class Tree < Array

      def folders
        select { |i| i.is_a?(Folder) }
      end

      def bookmarks
        select { |i| i.is_a?(Bookmark) }
      end

    end

    class Folder < Tree

      attr_accessor :name, :add_date, :last_modified, :personal_toolbar_folder, :id
      # sync: name

      def initialize(*args)
        super

        yield self if block_given?
      end

      def to_s(indent = 0)
        contents  = ["#{'  ' * indent}#{'* ' if personal_toolbar_folder}#{name}/"]
        contents += folders.map   { |f| f.to_s(indent + 1) }
        contents += bookmarks.map { |b| b.to_s(indent + 1) }
        contents.join("\n")
      end

    end

    class Bookmark

      attr_accessor :name, :href, :add_date, :last_visit, :last_modified, :last_charset, :shortcuturl, :icon, :id, :description  #, :schedule, :last_ping
      # sync: name, href, shortcuturl, icon, description

      def initialize
        yield self if block_given?
      end

      def to_s(indent = 0)
        "#{'  ' * indent}#{name} [#{href}]"
      end

    end

    attr_reader :input, :doc, :last_modified, :charset

    def initialize(input)
      @input = input
    end

    def doc
      @doc ||= Hpricot(input)
    end

    def last_modified
      @last_modified ||= doc.at('h1')[:last_modified].to_time
    end

    def charset
      @charset ||= doc.at('meta[@http-equiv="Content-Type"]')[:content][/charset=(\S+)/, 1]
    end

    def tree
      @tree ||= _parse(doc, Tree.new)
    end

    def folders
      tree.folders
    end

    def bookmarks
      tree.bookmarks
    end

    def to_s
      (folders.map { |f| f.to_s } + bookmarks.map { |b| b.to_s }).join("\n")
    end

    def write(file)
      File.open(file, 'w') { |f|
        f.puts '<!DOCTYPE NETSCAPE-Bookmark-file-1>'
        f.puts '<!-- This is an automatically generated file.'
        f.puts '     It will be read and overwritten.'
        f.puts '     DO NOT EDIT! -->'
        f.puts %Q{<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=#{charset}">}
        f.puts '<TITLE>Bookmarks</TITLE>'
        f.puts %Q{<H1 LAST_MODIFIED="#{last_modified}">Bookmarks</H1>}
        f.puts
      }
    end

    private

    def _parse(src, tree)
      (src/'/dl/dt').each { |dt|
        if h3 = dt.at('/h3')
          tree << Folder.new(_parse(dt, Tree.new)) { |f|
            f.name                    = h3.inner_html
            f.add_date                = h3[:add_date].to_time
            f.last_modified           = h3[:last_modified].to_time
            f.personal_toolbar_folder = h3[:personal_toolbar_folder] == 'true'
            f.id                      = h3[:id]
          }
        else
          a = dt.at('a')

          if dd = dt.next_sibling and dd.name == 'dd'
            description = dd.inner_html
          end

          tree << Bookmark.new { |b|
            b.name          = a.inner_html
            b.href          = a[:href]
            b.add_date      = a[:add_date].to_time
            b.last_visit    = a[:last_visit].to_time
            b.last_modified = a[:last_modified].to_time
            b.last_charset  = a[:last_charset]
            b.shortcuturl   = a[:shortcuturl]
            b.icon          = a[:icon]
            b.id            = a[:id]
            b.description   = description
          }
        end
      }

      tree
    end

  end

end

if $0 == __FILE__
  abort "Usage: #{$0} <bookmarks.html>" if ARGV.empty?

  bm = ARGV.first
  abort "File not found: #{bm}" unless File.readable?(bm)

  puts Bookmarks.new(bm)
end
