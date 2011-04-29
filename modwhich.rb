#! /usr/bin/env ruby

#--
###############################################################################
#                                                                             #
# modwhich -- Find the location of a library. Solution for Ruby Quiz          #
# "Where the Required Things Are" (#175) by Matthew Moss, 2008/08/29.         #
#                                                                             #
# Copyright (C) 2008-2011 Jens Wille <jens.wille@uni-koeln.de>                #
#                                                                             #
# modwhich is free software; you can redistribute it and/or modify it under   #
# the terms of the GNU Affero General Public License as published by the Free #
# Software Foundation; either version 3 of the License, or (at your option)   #
# any later version.                                                          #
#                                                                             #
# modwhich is distributed in the hope that it will be useful, but WITHOUT     #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or       #
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License #
# for more details.                                                           #
#                                                                             #
# You should have received a copy of the GNU Affero General Public License    #
# along with modwhich. If not, see <http://www.gnu.org/licenses/>.            #
#                                                                             #
###############################################################################
#++

begin
  require 'rubygems'
  require 'rubygems/commands/which_command'
rescue LoadError
end

class ModWhich

  @verbose, @recursive = false, false

  class << self

    include Enumerable

    attr_writer :verbose, :recursive

    def init(args = nil, recursive = recursive? || args.nil?)
      @args, @recursive = args, recursive

      @which, @load_order, @added_paths = {}, [], []

      unless Object.const_defined?(:SCRIPT_LINES__)
        Object.const_set(:SCRIPT_LINES__, {})
      end

      unless Object.ancestors.include?(Require)
        Object.send(:include, Require)
      end
    end

    def which(mod)
      self.require(mod)
      @which[mod] if @which
    end

    def require(mod, verbose = verbose?)
      if @which && !required?(mod)
        @load_order << mod
        current_paths = loaded_paths

        ret = recursive_verbose(verbose) {
          _modwhich_original_require(mod)
        }

        @added_paths.concat(loaded_paths - current_paths)
        @which[mod] = @added_paths.pop || gemwhich(mod)

        warn @which[mod] if verbose

        ret
      end
    end

    def required?(mod)
      @which && @which.has_key?(mod)
    end

    def verbose?
      @verbose
    end

    def recursive?
      @recursive
    end

    def recursive_verbose?(verbose)
      recursive? && !verbose.nil? && verbose != verbose?
    end

    def recursive_verbose(verbose)
      recursive_verbose = recursive_verbose?(verbose)
      self.verbose = verbose if recursive_verbose

      ret = yield

      self.verbose = !verbose if recursive_verbose

      ret
    end

    def include?(mod)
      !to_a.assoc(mod).nil?
    end

    def each
      if @load_order
        if @args
          @args.each { |mod| self.require(mod) }
          @load_order &= @args unless recursive?
          @args = nil
        end

        @load_order.each { |mod| yield mod, which(mod) }
      end
    end

    def to_h
      inject({}) { |h, (mod, path)| h.update(mod => path) }
    end

    private

    # basically equivalent to: <tt>%x{gem which #{mod}}.split(/\n/).last</tt>
    def gemwhich(mod)
      if defined?(Gem::Commands::WhichCommand)
        @gemwhich ||= Gem::Commands::WhichCommand.new
        @searcher ||= Gem::GemPathSearcher.new

        dirs = $LOAD_PATH

        if spec = @searcher.find(mod)
          dirs += @gemwhich.gem_paths(spec)
        end

        # return the last (only?) one
        @gemwhich.find_paths(mod, dirs).last
      end
    end

    def loaded_paths
      SCRIPT_LINES__.keys - (@which ? @which.values : [])
    end

  end

  module Require
    unless respond_to?(:_modwhich_original_require)
      alias_method :_modwhich_original_require, :require
    end

    def require(*args) ModWhich.require(*args) end
  end

end

if $0 == __FILE__
  progname = File.basename($0)

  usage = <<-EOT.gsub(/^\s+/, '')
    #{progname} [-v|--verbose] [-r|--recursive] <mod> ...
    #{progname} [-h|--help]
  EOT

  help      = ARGV.delete('-h') || ARGV.delete('--help')
  verbose   = ARGV.delete('-v') || ARGV.delete('--verbose')
  recursive = ARGV.delete('-r') || ARGV.delete('--recursive')

  abort usage if help || ARGV.empty?

  ModWhich.init(ARGV, recursive)

  ARGV.each { |mod| require mod, verbose }
else
  ModWhich.init
end

at_exit {
  ModWhich.each { |mod, path|
    warn "require '#{mod}' => #{path || 'NOT FOUND'}"
  } unless verbose || ModWhich.verbose?
}
