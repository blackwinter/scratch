class Trie

  class << self

    def build(&block)
      new(&block)
    end

    def from_file(file, &block)
      from_words(File.foreach(file), &block || :chomp)
    end

    def from_words(words)
      build { |trie|
        words.each { |word|
          trie.insert(block_given? ? yield(word) : word)
        }
      }
    end

  end

  def initialize
    self.root = Node.new
    yield root if block_given?
  end

  attr_accessor :root

  def each(&block)
    root.each(&block)
  end

  def size
    size = 0
    each { |node| size += 1 if node.word }
    size
  end

  def length
    length = 0
    each { |node| length += 1 }
    length
  end

  def inspect
    '#<%s:0x%x @size=%p, @length=%p>' % [
      self.class, object_id, size, length]
  end

  class Node

    def initialize
      self.word, self.children = nil, {}
    end

    attr_accessor :word, :children

    def each(&block)
      block[self]
      children.each_value { |node| node.each(&block) }
    end

    def insert(word)
      iterate(word) { self.class.new }.word = word
    end

    alias_method :<<, :insert

    def search(word)
      iterate(word) { return }.word
    end

    alias_method :[], :search

    def inspect
      '#<%s:0x%x @word=%p, @children=%p>' % [
        self.class, object_id, word, children.keys]
    end

    private

    def iterate(word)
      word.each_char.inject(self) { |node, char|
        node.children[char] ||= yield
      }
    end

  end

end
