module H2
  class Server
    class Stream
      class Response
        include HeaderStringifier

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
          @stream  = stream
          @headers = headers
          @body    = body
          @status  = status

          check_accept_encoding
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

        # send the headers and body out on +s+, an +HTTP2::Stream+ object, and
        # close the stream when complete.
        #
        # NOTE: +:status+ must come first?
        #
        def respond_on s
          headers = { STATUS_KEY => @status.to_s }.merge @headers
          s.headers stringify_headers(headers)
          if String === @body
            s.data @body
          else
            stream.log :error, "unexpected @body: #{caller[0]}"
          end
        rescue ::HTTP2::Error::StreamClosed
          stream.log :warn, "stream closed early by client"
        end

        # checks the request for accept-encoding headers and processes body
        # accordingly
        #
        def check_accept_encoding
          if accept = @stream.request.headers[ACCEPT_ENCODING_KEY]
            accept.split(',').map(&:strip).each do |encoding|
              case encoding
              when GZIP_ENCODING
                @body = ::Zlib.gzip @body
                @headers[CONTENT_ENCODING_KEY] = GZIP_ENCODING
                break

              # "deflate" has issues: https://zlib.net/zlib_faq.html#faq39
              #
              when DEFLATE_ENCODING
                @body = ::Zlib.deflate @body
                @headers[CONTENT_ENCODING_KEY] = DEFLATE_ENCODING
                break

              end
            end
          end
        end

        def to_s
          %{#{request.addr} "#{request.method} #{request.path} HTTP/2" #{status} #{content_length}}
        end
        alias to_str to_s

      end
    end
  end
end
