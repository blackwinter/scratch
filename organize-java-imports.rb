#! /usr/bin/env ruby

out, imp, buf, del, pkg, com = [], Hash.new { |h, k| h[k] = [] }, [], [], '', nil

ARGF.each { |line|
  out << line.dup

  line.sub!(/(?:\A|.*\s)\*\//, '') ? com = nil  : com ? next :
  line.sub!(/\/\*(?:\z|\s.*)/, '') ? com = true : nil

  line.sub!(/\/\/\s.*/, '')
  line.strip!

  next if line.empty?

  case line
    when /\Apackage\s+([\w.]+);/
      pkg = $1
    when /\Aimport\s+(.*?)([^.\s*]+)\s*;/
      ($1 == pkg + '.' ? del : imp[$2]) << $. - 1
    else
      line.scan(/\b(#{Regexp.union(*imp.keys)})\b/) {
        del.concat(imp.delete($1).drop(1)) if imp.key?($1)
      }
  end
}

del.concat(imp.values.flatten).uniq!

out.each_with_index { |line, num|
  next if del.include?(num)

  if line =~ /\A(?:\/\/)?import\s+/
    buf << line
  else
    puts buf.sort_by { |i| i.sub(/\A\/\//, '') }, line
    buf.clear
  end
}

puts buf

abort 'No package declaration!' if pkg.empty?
