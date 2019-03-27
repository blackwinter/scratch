#! /usr/bin/env ruby

require 'etc'
require 'json'
require 'net/http'
require 'zlib'

class EsSample

  DEFAULT_HOST   = 'http://localhost:9200'.freeze
  DEFAULT_COUNT  = 1
  DEFAULT_SIZE   = 1000
  DEFAULT_LIMIT  = Float::INFINITY
  DEFAULT_QUERY  = { match_all: {} }.freeze
  DEFAULT_SCROLL = '10s'.freeze

  SCROLL_PATH = '_search/scroll'.freeze
  GZIP_RE     = %r{\.gz(?:ip)?\z}i.freeze
  HEADER      = { 'Content-Type' => 'application/json' }.freeze

  NET = Hash.new { |h, k|
    h[k] = [uri = URI(k), Net::HTTP.new(uri.hostname, uri.port).tap { |http|
      http.use_ssl = uri.scheme == 'https'
      http.start
    }]
  }

  class << self

    def cli(argv = ARGV, prog = $0)
      trap(:INT) { exit 130 }

      params, opts = %W[[#{help = '--help'}]], {}

      flag = lambda { |short, long|
        params << "[#{short_switch = "-#{short}"}|#{long_switch = "--#{long}"}]"
        opts[long] = [argv.delete(short_switch), argv.delete(long_switch)].any?
      }

      opt = lambda { |key, name, multi = false, &block|
        params << "[#{switch = "-#{key}"} <#{name.upcase}>]#{'...' if multi}"

        block ||= lambda { |v| v }

        values = []

        while index = argv.index(switch)
          argv.delete_at(index)
          values << block[argv.delete_at(index)]
        end

        opts[name] = multi ? values : values.last unless values.empty?
      }

      list = lambda { |*args| opt.(*args) { |v| v.split(',') } }

      opt.(:P, :parallelism) { |p| Integer(p) unless p == '-' }
      opt.(:Q, :queuesize)   { |q| Integer(q) }
      opt.(:S, :scroll)
      opt.(:c, :count)       { |c| Integer(c) unless c == '-' }
      opt.(:h, :host)        { |h| h.sub(/\/*\z/, '/') }
      opt.(:l, :limit)       { |l| Integer(l) unless l == '-' }
      opt.(:o, :output)
      opt.(:q, :query)       { |q| JSON.parse(q) }
      opt.(:s, :size)        { |s| Integer(s) }

      existing = list[:e, :existing, true]
      missing  = list[:m, :missing,  true]

      if source_fields = list[:f, :source_fields] and source_fields.delete('-')
        source_fields.concat(existing.flatten) if existing
        source_fields.concat(missing.flatten)  if missing
      end

      list[:F, :stored_fields]
      list[:D, :data_fields]

      flag[:d, :delete]
      flag[:p, :pretty]
      flag[:r, :random]

      if argv.empty? || argv.include?(help)
        puts "Usage: #{prog} #{params.join(' ')} <INDEX>..."
        exit
      end

      begin
        yield EsSample.new(opts), argv
      rescue => err
        abort "ERROR: #{err} (#{err.backtrace.first})"
      end
    end

    def traverse(value, keys = [], *path)
      case value
        when Hash  then value.each { |k, v| traverse(v, keys, *path, k) }
        when Array then value.each { |   v| traverse(v, keys, *path)    }
      end

      path.empty? ? keys.sort!.tap(&:uniq!) : keys << path.join('.')
    end

  end

  def initialize(opts = {})
    opts.each { |k, v| respond_to?(m = "#{k}=") ?
      send(m, v) : raise(ArgumentError, "invalid argument: #{k}") }

    @host        ||= DEFAULT_HOST
    @count       ||= DEFAULT_COUNT unless instance_variable_defined?(:@count)
    @size        ||= DEFAULT_SIZE
    @limit       ||= DEFAULT_LIMIT
    @query       ||= DEFAULT_QUERY
    @scroll      ||= DEFAULT_SCROLL
    @parallelism ||= Etc.nprocessors unless instance_variable_defined?(:@parallelism)
    @queuesize   ||= size

    @conditions = { existing => true, missing => false }.delete_if { |k,| !k }
  end

  attr_accessor :count, :data_fields, :existing, :source_fields, :stored_fields,
                :host, :limit, :missing, :output, :parallelism, :pretty,
                :queuesize, :query, :random, :scroll, :size

  attr_reader :base, :conditions, :docs, :scroll_ids, :type

  attr_writer :delete

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

  private

  def reset(base, *rest)
    @base, @type, @docs, @scroll_ids = base, nil, [], []
    def docs.<<(*); end if rest.empty?
  end

  def fetch_base(&block)
    q = !random ? make_query(query).tap { |r| r[:sort] = %w[_doc] } :
      make_query(function_score: { query: query, random_score: {} })

    refresh(base)

    async(block) { |_block|
      id, limit = fetch("#{base}/_search?scroll=#{scroll}", q, &_block), self.limit

      while id && (limit -= size) > 0
        id = fetch("#{SCROLL_PATH}?scroll=#{scroll}", scroll_id: id, &_block)
      end

      clear_scroll unless scroll_ids.empty?
    }

    delete(base) if @delete
  end

  def fetch_rest(*args)
    args.each { |index|
      refresh(index)

      write(index) { |block|
        async(block) { |_block|
          docs.each_slice(size) { |ids|
            iterate(post("#{index}/_search",
              make_query(ids: { type: type, values: ids })), &_block)
          }
        }
      }

      delete(index) if @delete
    }
  end

  def refresh(index)
    post("#{index}/_refresh")
  end

  def async(block)
    return yield block unless parallelism

    queue, mutex = SizedQueue.new(queuesize), Mutex.new

    threads = Array.new(parallelism) { Thread.new {
      while args = queue.pop
        mutex.synchronize { block[*args] }
      end
    } }

    Thread.new { yield lambda { |*args| queue << args } }.join

    queue.close
    threads.each(&:join)
  end

  def clear_scroll
    delete(SCROLL_PATH, scroll_id: scroll_ids)
  end

  def write(index = nil, &block)
    write = lambda { |io| block[lambda { |doc|
      hash = doc['_source']
      more = doc['fields'] and (hash ||= {})['_'] = more

      io.puts(dump(hash)) if hash
    }] }

    output == '-' ? write[$stdout] : begin
      puts name = output || "#{index || base}.jsonl"

      File.open(name, index && output ? 'a' : 'w') { |f|
        name !~ GZIP_RE ? write[f] : begin
          gz = Zlib::GzipWriter.new(f)
          write[gz]
        ensure
          gz&.close
        end
      }
    end
  end

  def make_query(hash)
    {
      _source:          source_fields || !(data_fields || stored_fields),
      fielddata_fields: data_fields, # ES >= 5.0: docvalue_fields
      fields:           stored_fields,
      query:            hash,
      size:             size
    }
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

  def post(path, data = {})
    uri, http = NET[host]
    uri = uri.merge(path)

    try = 2

    res = begin
      http.post(uri.request_uri, data.to_json, HEADER)
    rescue EOFError => err
      (try -= 1) > 0 ? (warn err; retry) : raise
    end

    raise "#{res.code} #{res.msg} - #{uri}" unless res.is_a?(Net::HTTPOK)

    json = JSON.parse(res.body)
    json.key?('error') ? raise(json.inspect) : json
  end

  def delete(path, body = nil)
    uri, http = NET[host]

    req = Net::HTTP::Delete.new(uri.merge(path).request_uri, HEADER)
    req.body = body.to_json if body

    http.request(req)
  end

  def iterate(json, &block)
    json['hits']['hits'].sort_by { |doc| doc['_id'] }.each(&block)
  end

  def dump(hash)
    pretty ? JSON.pretty_generate(hash) : JSON.fast_generate(hash)
  end

end

EsSample.cli { |es, args| es.run(*args) } if $0 == __FILE__
