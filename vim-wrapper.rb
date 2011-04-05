#! /usr/bin/ruby

name = File.basename($0)
cmd  = (%x{which -a #{name}}.split($/) - [$0]).first

abort "#{name}: command not found" unless cmd && File.executable?(cmd)

re = %r{(.+):(\d+)(?::.*)?\z}

argv = ARGV.dup.delete_if { |arg|
  system(cmd, $1, "+#{$2}") || true if arg =~ re && File.exist?($1)
}

exec(cmd, *argv) if ARGV.empty? || !argv.empty?
