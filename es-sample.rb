#! /usr/bin/env ruby

require 'net/http'
require 'json'
require 'zlib'

class EsSample

  DEFAULT_HOST  = 'http://localhost:9200'.freeze
  DEFAULT_COUNT = 1
  DEFAULT_SIZE  = 1000
  DEFAULT_LIMIT = Float::INFINITY
  DEFAULT_QUERY = { match_all: {} }.freeze

  SCROLL      = '10s'.freeze
  SCROLL_PATH = '_search/scroll'.freeze
  GZIP_RE     = %r{\.gz(?:ip)?\z}i.freeze
  HEADER      = { 'Content-Type' => 'application/json' }.freeze

  NET = Hash.new { |h, k|
    h[k] = [uri = URI(k), Net::HTTP.new(uri.hostname, uri.port).tap { |http|
      http.use_ssl = uri.scheme == 'https'
      http.start
    }]
  }

  def self.traverse(value, keys = [], *path)
    case value
      when Hash  then value.each { |k, v| traverse(v, keys, *path, k) }
      when Array then value.each { |   v| traverse(v, keys, *path)    }
    end

    path.empty? ? keys.sort!.uniq! : keys << path.join('.')
  end

  def initialize(opts = {})
    opts.each { |k, v| respond_to?(m = "#{k}=") ?
      send(m, v) : raise(ArgumentError, "invalid argument: #{k}") }

    @host  ||= DEFAULT_HOST
    @count ||= DEFAULT_COUNT
    @size  ||= DEFAULT_SIZE
    @limit ||= DEFAULT_LIMIT
    @query ||= DEFAULT_QUERY

    @conditions = { existing => true, missing => false }.delete_if { |k,| !k }
  end

  def each(base, &block)
    return enum_for(__method__, base) unless block

    reset(base)
    fetch_base(&block)
  end

  def run(base, *rest)
    reset(base, *rest)

    write { |block| fetch_base(&block) }
    fetch_rest(*rest) if type
  end

  attr_accessor :host, :count, :size, :limit, :output, :query,
                :existing, :missing, :fields, :random, :pretty

  attr_reader :conditions, :base, :type, :docs, :scroll_ids

  private

  def reset(base, *rest)
    @base, @type, @docs, @scroll_ids = base, nil, [], []
    def docs.<<(*); end if rest.empty?
  end

  def fetch_base(&block)
    q = !random ? make_query(query).tap { |r| r[:sort] = %w[_doc] } :
      make_query(function_score: { query: query, random_score: {} })

    id, limit = fetch("#{base}/_search?scroll=#{SCROLL}", q, &block), self.limit

    while id && (limit -= size) > 0
      id = fetch("#{SCROLL_PATH}?scroll=#{SCROLL}", scroll_id: id, &block)
    end

    clear_scroll unless scroll_ids.empty?
  end

  def fetch_rest(*args)
    args.each { |index| write(index) { |block|
      docs.each_slice(size) { |ids| iterate(post("#{index}/_search",
        make_query(ids: { type: type, values: ids })), &block) } } }
  end

  def clear_scroll
    uri, http = NET[host]

    req = Net::HTTP::Delete.new(uri.merge(SCROLL_PATH).request_uri, HEADER)
    req.body = { scroll_id: scroll_ids }.to_json

    http.request(req)
  end

  def write(index = nil, &block)
    write = lambda { |io| block[lambda { |doc|
      hash = doc['_source'] and io.puts(dump(hash)) }] }

    output == '-' ? write[$stdout] : begin
      puts name = output || "#{index || base}.jsonl"

      File.open(name, index && output ? 'a' : 'w') { |f|
        name =~ GZIP_RE ? Zlib::GzipWriter.new(f).tap(&write).close : write[f]
      }
    end
  end

  def make_query(hash)
    { query: hash, _source: fields || true, size: size }
  end

  def fetch(*args, &block)
    json = post(*args)

    id = json['_scroll_id']
    scroll_ids << id if id

    id unless iterate(json) { |doc|
      unless conditions.empty?
        keys = self.class.traverse(doc['_source'])

        next if conditions.any? { |lists, condition|
          lists.all? { |list|
            list.any? { |glob|
              keys.any? { |key|
                File.fnmatch?(glob, key) } ^ condition } } }
      end

      break [] if count && (self.count -= 1) < 0

      @type ||= doc['_type']
      docs << doc['_id']
      block[doc]
    }.empty?
  end

  def post(path, data)
    uri, http = NET[host]
    uri = uri.merge(path)

    res = http.post(uri.request_uri, data.to_json, HEADER)
    raise "#{res.code} #{res.msg} - #{uri}" unless res.is_a?(Net::HTTPOK)

    json = JSON.parse(res.body)
    json.key?('error') ? raise(json.inspect) : json
  end

  def iterate(json, &block)
    json['hits']['hits'].sort_by { |doc| doc['_id'] }.each(&block)
  end

  def dump(hash)
    pretty ? JSON.pretty_generate(hash) : JSON.fast_generate(hash)
  end

end

if $0 == __FILE__
  trap(:INT) { exit 130 }

  params, opts = %W[[#{help = '--help'}]], {}

  flag = lambda { |short, long|
    params << "[#{short_switch = "-#{short}"}|#{long_switch = "--#{long}"}]"
    opts[long] = [ARGV.delete(short_switch), ARGV.delete(long_switch)].any?
  }

  opt = lambda { |key, name, multi = false, &block|
    params << "[#{switch = "-#{key}"} <#{name.upcase}>]#{'...' if multi}"

    block ||= lambda { |v| v }

    values = []

    while index = ARGV.index(switch)
      ARGV.delete_at(index)
      values << block[ARGV.delete_at(index)]
    end

    opts[name] = multi ? values : values.last unless values.empty?
  }

  list = lambda { |*args| opt.(*args) { |v| v.split(',') } }

  opt.(:h, :host)  { |h| h.sub(/\/*\z/, '/') }
  opt.(:c, :count) { |c| Integer(c) unless c == '-' }
  opt.(:s, :size)  { |s| Integer(s) }
  opt.(:l, :limit) { |l| Integer(l) unless l == '-' }
  opt.(:o, :output)
  opt.(:q, :query) { |q| JSON.parse(q) }

  existing = list[:e, :existing, true]
  missing  = list[:m, :missing,  true]

  if fields = list[:f, :fields] and fields.delete('-')
    fields.concat(existing.flatten) if existing
    fields.concat(missing.flatten)  if missing
  end

  flag[:r, :random]
  flag[:p, :pretty]

  if ARGV.empty? || ARGV.include?(help)
    puts "Usage: #{$0} #{params.join(' ')} <INDEX>..."
    exit
  end

  begin
    EsSample.new(opts).run(*ARGV)
  rescue => err
    abort "ERROR: #{err}"
  end
end
