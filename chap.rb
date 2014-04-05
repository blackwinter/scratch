# cf. <http://github.com/dscape/rudolph/blob/master/src/lib/rudolph/crypt.rb>

require 'openssl'
require 'forwardable'

class Client

  attr_reader :trusted_keys

  def initialize(trusted_keys = {})
    @trusted_keys = trusted_keys
  end

  def trusting?(server)
    if key = trusted_keys[server.name]
      # see if server can correctly decrypt our encrypted message
      server.decrypt(encrypt(token = generate_token, key)) == token
    end
  end

  def generate_token
    # well, be creative ;-)
    "#{rand}--#{$$}--#{Time.now.to_f}"
  end

  def encrypt(token, key)
    key.public_encrypt(token)
  end

end

class Server

  attr_reader :name, :private_key, :public_key

  private :private_key

  KEY_LENGTH = 2 ** 10

  def initialize(name)
    @name = name

    generate_keys
  end

  def decrypt(token)
    private_key.private_decrypt(token)
  end

  private

  def generate_keys
    keypair = OpenSSL::PKey::RSA.generate(KEY_LENGTH)

    @private_key = OpenSSL::PKey::RSA.new(keypair.to_pem)
    @public_key  = OpenSSL::PKey::RSA.new(keypair.public_key.to_pem)
  end

end

class ManInTheMiddle

  extend Forwardable

  def initialize(good_guy)
    @good_guy = good_guy
  end

  # pretend to be good guy
  def_delegators :@good_guy, :name, :public_key

  def decrypt(token)
    # um, don't know private key so try public -- whatever...
    public_key.private_decrypt(token)
  rescue OpenSSL::PKey::RSAError
    # didn't work, eh? ("private key needed.: no start line")
    # let's try something else -- can you do any better? ;-)
    Client.new.generate_token
  end

end

if $0 == __FILE__

  require 'rspec/autorun'

  describe Client do

    before do
      @good_guy = Server.new('GoodGuy')
      @villain  = ManInTheMiddle.new(@good_guy)

      @client = Client.new(@good_guy.name => @good_guy.public_key)
    end

    it "should be trusting good guy" do
      @client.should be_trusting(@good_guy)
    end

    it "should not be trusting man-in-the-middle" do
      @client.should_not be_trusting(@villain)
    end

  end

end
