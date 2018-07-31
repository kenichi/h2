module H2
  class Server
    class Stream
      class Response

        attr_reader :body, :content_length, :headers, :status, :stream

        # build a new +Response+ object
        #
        # @param [H2::Server::Stream] stream: Stream instance associated with this response
        # @param [Integer] status: HTTP status code
        # @param [Hash] headers: response headers
        # @param [String,#each] body: response body. NOTE: may be any object that
        #                             `respond_to? :each` which both yields and returns
        #                             String objects.
        #
        # @return [H2::Server::Stream::Response]
        #
        def initialize stream:, status:, headers: {}, body: ''
          @stream     = stream
          @headers    = headers
          @body       = body
          self.status = status

          init_content_length
        end

        # sets the content length in the headers by the byte size of +@body+
        #
        def init_content_length
          return if @headers.any? {|k,_| k.downcase == CONTENT_LENGTH_KEY}
          return if @body.respond_to?(:each)
          @content_length = case
                            when String === @body
                              @body.bytesize
                            when NilClass
                              '0'
                            else
                              raise TypeError, "can't render #{@body.class} as a response body"
                            end

          @headers[CONTENT_LENGTH_KEY] = @content_length
        end

        # the corresponding +Request+ to this +Response+
        #
        def request
          stream.request
        end

        # send the headers and body out on +s+, an +HTTP2::Stream+ object
        #
        # NOTE: +:status+ must come first?
        #
        def respond_on s
          headers = { STATUS_KEY => @status.to_s }.merge @headers
          s.headers stringify_headers(headers)
          case
          when String === @body
            s.data @body
          when @body.respond_to?(:each)
            final = @body.each {|res| s.data res, end_stream: false}
            s.data final
          else
            stream.log :error, "unexpected @body: #{caller[0]}"
          end
        rescue ::HTTP2::Error::StreamClosed => sc
          stream.log :warn, "stream closed early by client"
        end

        # sets +@status+ either from given integer value (HTTP status code) or by
        # mapping a +Symbol+ in +Reel::Response::SYMBOL_TO_STATUS_CODE+ to one
        #
        def status= status
          case status
          when Integer
            @status = status
          when Symbol
            if code = ::Reel::Response::SYMBOL_TO_STATUS_CODE[status]
              self.status = code
            else
              raise ArgumentError, "unrecognized status symbol: #{status}"
            end
          else
            raise TypeError, "invalid status type: #{status.inspect}"
          end
        end

        def to_s
          %{#{request.addr} "#{request.method} #{request.path} HTTP/2" #{status} #{content_length}}
        end
        alias to_str to_s

        private

        def stringify_headers hash
          hash.keys.each do |k|
            hash[k] = hash[k].to_s unless String === hash[k]
            if Symbol === k
              key = k.to_s.gsub '_', '-'
              hash[key] = hash.delete k
            end
          end
          hash
        end

      end
    end
  end
end
