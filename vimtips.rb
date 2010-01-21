#! /usr/bin/ruby

require 'yaml'
require 'erb'

base = File.join(File.dirname(__FILE__), File.basename(__FILE__, '.rb'))
path = "#{base}.yaml"

to   = File.read("#{base}.to").gsub(/\n+/, ' ')
tmpl = File.read("#{base}.erb")
tips = YAML.load_file(path)
tip  = tips.shift  #tips[rand(tips.size)]

comment = tip[:comment]
command = tip[:command]
source  = tip[:source]

subject = tip[:subject] || (comment ? "#{comment[0..25]}..." : '...')
cmd = %Q{/usr/bin/mail -e -s "[VimTip] #{subject.gsub(/"/, '\"')}" #{to}}

IO.popen(cmd, 'w') { |mail|
  mail.puts ERB.new(tmpl).result(binding)
}

File.open(path, 'w') { |f|
  YAML.dump(tips, f)
}
