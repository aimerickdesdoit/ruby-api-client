require 'uri'
require 'net/https'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/hash/conversions'
require 'json'
require 'benchmark'

class ApiClient
  
  class_attribute :redis
  class_attribute :logger
  
  def initialize(domain, options = {})
    @options = options
    @options = {
      :secure         => false,
      :verify_mode    => OpenSSL::SSL::VERIFY_PEER,
      :domain         => domain,
      :port           => nil,
      :username       => nil,
      :password       => nil,
      :http_block     => nil,
      :on_setup_request  => nil
    }.merge(@options)
  end
  
  def cache(cache_id, ttl = nil, &block)
    data = self.class.redis.get cache_id
    if data.blank?
      data = yield
      self.class.redis.setex cache_id, ttl, data.to_json
    else
      data = receive_json_data data
    end
    data
  end
  
  def get(path, data = {})
    path << "?#{Rack::Utils.build_nested_query data}" if data.count > 0
    api_response_for(:get, path)
  end
  
  def post(path, data = {})
    @options[:on_setup_request] = lambda { |request| request.set_form_data data }
    response = api_response_for(:post, path)
    @options[:on_setup_request] = nil
    response
  end
  
  def secure?
    @options[:secure]
  end
  
  private
  
  def api_response_for(method, path)
    # construction de l'URI
    uri = URI.parse("#{endpoint}#{path}")
    
    # récupération de la réponse
    response = response_for(method, uri)
    
    response_code = response.code.to_i
    unless (200..210).include? response.code.to_i
      raise response.body.gsub(/(<.*?>)/, '')
    end
    
    # traitement de la réponse
    receive_data response
  end
  
  def receive_data(data)
    data = data.body if data.respond_to? :body
    data = data.to_s.strip
    
    if data.start_with?('<?xml')
      receive_xml_data data
    elsif data.start_with?('{') && data.end_with?('}')
      receive_json_data data
    else
      data
    end
  end

  def receive_xml_data(data)
    Hash.from_xml(data)
  end

  def receive_json_data(data)
    JSON.parse(data)
  end

  def endpoint
    port = @options[:port] ? ":#{@options[:port]}" : nil
    "#{secure? ? 'https' : 'http'}://#{@options[:domain]}#{port}"
  end
  
  ###########################
  ### Méthodes génériques ###
  ###########################
  
  def response_for(method, uri)
    # paramètrage de la connexion
    http = setup_http_connection(uri)
    
    # construction de la requête
    request = setup_request(method, uri)
    
    # logs de la requête comme dans Wrest::Curl::Request
    prefix = "#{method.to_s.upcase} #{request.hash} #{http.hash}"
    self.class.logger.info "<- (#{prefix}) #{uri.to_s}" if self.class.logger
    
    response = nil
    time = Benchmark.realtime { response = http.request(request) }
    
    self.class.logger.info "-> (#{prefix}) %s (%d bytes %.2fs)" % [response.message, response.body ? response.body.length : 0, time] if self.class.logger
    
    response
  end
  
  def setup_http_connection(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    if secure?
      http.use_ssl      = true
      http.ca_file      = @options[:ca_file]
      http.verify_mode  = @options[:verify_mode]
    else
      http.use_ssl      = false
    end
    http
  end

  def setup_request(method, uri)
    query = uri.query ? "?#{uri.query}" : nil
    request = Net::HTTP.const_get(method.to_s.capitalize).new("#{uri.path}#{query}")
    basic_auth request
    @options[:on_setup_request].call(request) if @options[:on_setup_request]
    request
  end
  
  def basic_auth(request)
    if @options[:username] && @options[:password]
      request.basic_auth(@options[:username], @options[:password])
    end
  end
  
end