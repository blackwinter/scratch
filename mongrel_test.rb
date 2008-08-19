#! /usr/bin/ruby

require 'rubygems'
require 'mongrel'

class TestPlugin < GemPlugin::Plugin '/handlers'
  include Mongrel::HttpHandlerPlugin

  def process(request, response)
    response.start(200) do |head, out|
      head['Content-Type'] = 'text/plain'
      out.write("#{options[:cmd]} = " << `#{options[:cmd]}`) if options[:cmd]
    end

    STDERR.puts 'Request was:'
    STDERR.puts request.params.to_yaml
  end
end

Mongrel::Configurator.new(:host => '0.0.0.0') do
  if ARGV.delete('-d')
    daemonize :cwd => Dir.pwd, :log_file => 'mongrel.log'
    File.open('mongrel.pid', 'w') { |f| f.puts Process.pid }
  end

  listener :port => 3333 do
    uri '/', :handler => plugin('/handlers/testplugin', :cmd => ARGV.first)
  end

  trap('INT') { stop }

  run
end.join
