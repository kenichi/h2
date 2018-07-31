module H2
  class Server
    class Stream
      class Request

        # a case-insensitive hash that also handles symbol translation i.e. s/_/-/
        #
        HEADER_HASH = Hash.new do |hash, key|
          k = key.to_s.upcase
          k.gsub! '_', '-' if Symbol === key
          _, value = hash.find {|header_key,v| header_key.upcase == k}
          hash[key] = value if value
        end

        attr_reader :body, :headers, :stream

        def initialize stream
          @stream  = stream
          @headers = HEADER_HASH.dup
          @body    = ''
        end

        # retreive the IP address of the connection
        #
        def addr
          @addr ||= @stream.connection.socket.peeraddr[3] rescue nil
        end

        # retreive the authority from the stream request headers
        #
        def authority
          @authority ||= headers[AUTHORITY_KEY]
        end

        # retreive the HTTP method as a lowercase +Symbol+
        #
        def method
          return @method unless @method.nil?
          @method = headers[METHOD_KEY]
          @method = @method.downcase.to_sym if @method
          @method
        end

        # retreive the path from the stream request headers
        #
        def path
          @path ||= headers[PATH_KEY]&.split('?')&.first
        end

        # retreive the query string from the stream request headers
        #
        def query_string
          return @query_string if defined?(@query_string)
          @query_string = headers[PATH_KEY].index '?'
          return if @query_string.nil?
          @query_string = headers[PATH_KEY][(@query_string + 1)..-1]
        end

        # retreive the scheme from the stream request headers
        #
        def scheme
          @scheme ||= headers[SCHEME_KEY]
        end

        # respond to this request on its stream
        #
        def respond status:, headers: {}, body: ''
          @stream.respond status: status, headers: headers, body: body
        end

      end
    end
  end
end
