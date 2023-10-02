#! /usr/bin/env ruby

out, imp, buf, del, pkg, com, idx =
  [], Hash.new { |h, k| h[k] = [] }, [], [], nil, nil, -1

ARGF.each { |line|
  out[idx += 1] = line.dup

  line.sub!(/(?:\A|.*\s)\*\//, '') ? com = nil  : com ? next :
  line.sub!(/\/\*(?:\z|\s.*)/, '') ? com = true : nil

  line.sub!(/\/\/\s.*/, '')
  line.strip!

  next if line.empty?

  case line
    when /\Apackage\s+([\w.]+);/
      pkg = $1 + '.'
    when /\Aimport\s+(.*?)([^.\s*]+)\s*;/
      ($1 == pkg ? del : imp[$2]) << idx
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
    puts buf.sort_by { |i| i.sub(/\A\/\//, '').sub(/;\Z/, '') }, line
    buf.clear
  end
}

puts buf

abort 'No package declaration!' unless pkg
