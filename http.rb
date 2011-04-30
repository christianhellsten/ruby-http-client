require 'net/http'
require 'net/https'
require 'uri' # there be bugs here
require "addressable/uri" # no more URI::InvalidURIError: bad URI(is not URI?)

class HTTP
  class << self
    def get(url, options = {})
      execute(url, options)
    end

    def post(url, options = {})
      options = { :method => :post }.merge(options)
      execute(url, options)
    end

    def encoding(response)
      return $1.downcase if response['content-type'] =~ /charset=(.*)/i
      return $1.downcase if response.body =~ /<meta.*?charset=([^"'>]+)/mi
    end

    protected

      def proxy
        http_proxy = ENV["http_proxy"]
        Addressable::URI.parse(http_proxy) rescue nil
      end

      def to_uri(url)
        if !url.respond_to?(:scheme)
          url = Addressable::URI.parse(url)
        end
        url
      end

      def execute(url, options = {})
        options = { :parameters => {}, :debug => false, :follow_redirects => true,
                    :http_timeout => 60, :method => :get, 
                    :headers => {}, :redirect_count => 0, 
                    :max_redirects => 10 }.merge(options)

        url = to_uri(url)
        
        if proxy
          http = Net::HTTP::Proxy(proxy.host, proxy.port).new(url.host, url.port)
        else
          http = Net::HTTP.new(url.host, url.port)
        end
        
        if url.scheme == 'https'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        
        http.open_timeout = http.read_timeout = options[:http_timeout]
        
        http.set_debug_output $stderr if options[:debug]
        
        request = case options[:method]
          when :post
            request = Net::HTTP::Post.new(url.request_uri)
            request.set_form_data(options[:parameters])
            request
          else
            Net::HTTP::Get.new(url.request_uri)
        end

        options[:headers].each { |key, value| request[key] = value }
        response = http.request(request)

        # Handle redirection
        if options[:follow_redirects] && response.kind_of?(Net::HTTPRedirection)      
          options[:redirect_count] += 1

          if options[:redirect_count] > options[:max_redirects]
            raise "Too many redirects (#{options[:redirect_count]}): #{url}" 
          end

          redirect_url = redirect_url(response)

          if redirect_url.start_with?('/')
            url = to_uri("#{url.scheme}://#{url.host}#{redirect_url}")
          else
            url = to_uri(redirect_url)
          end

          response, url = execute(url, options)
        end

        [response, url.to_s]
      end

      # From http://railstips.org/blog/archives/2009/03/04/following-redirects-with-nethttp/
      def redirect_url(response)
        if response['location'].nil?
          response.body.match(/<a href=\"([^>]+)\">/i)[1]
        else
          response['location']
        end
      end
  end
end
