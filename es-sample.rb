#! /usr/bin/env ruby

require 'net/http'
require 'json'
require 'zlib'

trap(:INT) { exit 130 }

opts = %W[[#{help = '--help'}]]

flag = lambda { |short, long|
  opts << "[#{short_switch = "-#{short}"}|#{long_switch = "--#{long}"}]"
  [ARGV.delete(short_switch), ARGV.delete(long_switch)].compact.first
}

opt = lambda { |key, value, default = nil, multi = false, &block|
  opts << "[#{switch = "-#{key}"} <#{value}>]#{'...' if multi}"

  block ||= lambda { |v| v }

  values = []

  while index = ARGV.index(switch)
    ARGV.delete_at(index)
    values << block[ARGV.delete_at(index)]
  end

  values.empty? ? default : multi ? values : values.last
}

host     = opt.(:h, :HOST, 'http://localhost:9200') { |h| h.sub(/\/*\z/, '/') }
count    = opt.(:c, :COUNT, 1) { |c| Integer(c) unless c == '-' }
size     = opt.(:s, :SIZE, 1000) { |s| Integer(s) }
output   = opt.(:o, :OUTPUT)
query    = opt.(:q, :QUERY, match_all: {}) { |q| JSON.parse(q) }
existing = opt.(:e, :EXISTING, nil, true) { |e| e.split(',') }
missing  = opt.(:m, :MISSING,  nil, true) { |m| m.split(',') }

if fields = opt.(:f, :FIELDS) { |f| f.split(',') } and fields.delete('-')
  fields.concat(existing.flatten) if existing
  fields.concat(missing.flatten)  if missing
end

random = flag[:r, :random]
pretty = flag[:p, :pretty]

if ARGV.empty? || ARGV.include?(help)
  puts "Usage: #{$0} #{opts.join(' ')} <INDEX>..."
  exit
end

dump, match = JSON.method("#{pretty ? :pretty : :fast}_generate"),
  random ? { function_score: { query: query, random_score: {} } } : query

base, scroll, type, docs, gz = ARGV.shift, '10s', nil, [], /\.gz(?:ip)?\z/i

def docs.<<(*); end if ARGV.empty?

net = Hash.new { |h, k|
  h[k] = [uri = URI(k), Net::HTTP.new(uri.hostname, uri.port).tap { |http|
    http.use_ssl = uri.scheme == 'https'
    http.start
  }]
}

post = lambda { |path, data|
  uri, http = net[host]
  uri = uri.merge(path)

  res = http.post(uri.request_uri, data.to_json)
  abort "ERROR: #{res.code} #{res.msg} - #{uri}" unless res.is_a?(Net::HTTPOK)

  json = JSON.parse(res.body)
  json.key?('error') ? abort(json.inspect) : json
}

each = lambda { |json, &block|
  json['hits']['hits'].sort_by { |doc| doc['_id'] }.each(&block) }

paths = lambda { |value, keys, *path|
  case value
    when Hash  then value.each { |k, v|
      paths[v, keys << (_p = path + [k]).join('.'), *_p] }
    when Array then value.each { |v| paths[v, keys, *path] }
  end
}

fetch = lambda { |*args, &block|
  json = post[*args]
  json['_scroll_id'] unless each.(json) { |doc|
    paths[doc['_source'], keys = []]

    next if existing && !existing.any? { |list| (list - keys).empty? }
    next if missing  && !missing.any?  { |list| (list & keys).empty? }

    break [] if count && (count -= 1) < 0

    type ||= doc['_type']
    docs << doc['_id']
    block[doc]
  }.empty?
}

write = lambda { |index = nil, &block|
  b = lambda { |io| block[lambda { |doc|
    c = doc['_source'] and io.puts(dump[c]) }] }

  output == '-' ? b[$stdout] : begin
    puts name = output || "#{index || base}.jsonl"

    File.open(name, index && output ? 'a' : 'w') { |f|
      name =~ gz ? Zlib::GzipWriter.new(f).tap(&b).close : b[f] }
  end
}

make_query = lambda { |hash|
  { query: hash, _source: fields || true, size: size } }

write.() { |block|
  q = make_query[match]
  q[:sort] = %w[_doc] unless random

  id = fetch.("#{base}/_search?scroll=#{scroll}", q, &block)

  while id
    id = fetch.("_search/scroll?scroll=#{scroll}", scroll_id: id, &block)
  end
}

ARGV.each { |index| write.(index) { |block|
  docs.each_slice(size) { |ids| each.(post["#{index}/_search",
    make_query[ids: { type: type, values: ids }]], &block) } } } if type
