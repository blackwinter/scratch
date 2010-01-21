#! /usr/bin/ruby

#--
###############################################################################
#                                                                             #
# meme -- Merge multiple external repositories                                #
#                                                                             #
# Copyright (C) 2010 Jens Wille                                               #
#                                                                             #
# Authors:                                                                    #
#     Jens Wille <jens.wille@uni-koeln.de>                                    #
#                                                                             #
# meme is free software; you can redistribute it and/or modify it under the   #
# terms of the GNU General Public License as published by the Free Software   #
# Foundation; either version 3 of the License, or (at your option) any later  #
# version.                                                                    #
#                                                                             #
# meme is distributed in the hope that it will be useful, but WITHOUT ANY     #
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS   #
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more       #
# details.                                                                    #
#                                                                             #
# You should have received a copy of the GNU General Public License along     #
# with meme. If not, see <http://www.gnu.org/licenses/>.                      #
#                                                                             #
###############################################################################
#++

module MeMe

  extend self

  def update(target, repos = {})
    repos.sort.each { |name, config|
      update_repo(dir = File.join(target, dot = ".#{name}"), config[:repo])
      update_symlinks(dir, config[:files], dot, target) if File.directory?(dir)
    }
  end

  def update_repo(dir, repo)
    case repo
      when /\Agit:\/\//, /\.git\z/
        if File.directory?(dir)
          Dir.chdir(dir) { git :pull, :origin, :master }
        else
          git :clone, repo, dir
        end
      #when /\Asvn:\/\//, /\/svn\//
      #when /\Arsync:\/\//
    end
  end

  def update_symlinks(dir, files, src_d, dst_d)
    srcdst(all_files = Dir["#{dir}/*"], src_d, dst_d) { |src, dst|
      File.unlink(dst) if File.symlink?(dst) && File.readlink(dst) == src
    }

    srcdst(files || all_files, src_d, dst_d) { |src, dst|
      File.symlink(src, dst) unless File.exists?(dst)
    }
  end

  private

  def git(*args)
    system('git', *args.map { |arg| arg.to_s })
  end

  def srcdst(files, src_d, dst_d)
    files.each { |path|
      file = File.basename(path)
      yield File.join(src_d, file), File.join(dst_d, file)
    }
  end

end

if $0 == __FILE__
  require 'yaml'

  target = ARGV.first || Dir.pwd
  config = File.join(target, 'meme.yaml')

  abort "no such directory: #{target}" unless File.directory?(target)
  abort "no such file: #{config}"      unless File.readable?(config)

  MeMe.update(target, YAML.load_file(config))
end
