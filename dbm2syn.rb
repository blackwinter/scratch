#! /usr/bin/ruby

abort "Usage: #{$0} <dbm> <syn> [<key>]" unless [2, 3].include?(ARGV.size)

STDOUT.sync = true

rec, syn = {}, Hash.new { |h, k| h[k] = [] }

ID_RE  = %r{\AID:(.*)}
KEY_RE = %r{\A(#{ARGV[2] || '.*?'}):(.*)}
REC_RE = %r{\A&&&\z}
SEP_RE = %r{\*}

File.foreach(ARGV[0]) { |line|
  print '.' if $. % 10_000 == 0

  case line.chomp
    when ID_RE
      rec[:id] = $1
    when KEY_RE
      (rec[$1] ||= []) << $2
    when REC_RE
      if id = rec.delete(:id)
        rec.values.each { |value|
          warn "#{id}: #{value}" if value =~ SEP_RE

          syn[value] << id
        }
      end

      rec = {}
  end
}

puts

syn.sort!

puts

File.open(ARGV[1], 'w') { |f|
  syn.each_with_index { |(value, ids), index|
    print '.' if index % 1_000 == 0

    f.puts "#{value}*#{ids.sort.uniq.join('|')}"
  }
}

puts
