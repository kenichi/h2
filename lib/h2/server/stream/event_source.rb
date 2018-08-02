module H2
  class Server
    class Stream
      class EventSource
        include HeaderStringifier

        DATA_TEMPL  = "data: %s\n\n"
        EVENT_TEMPL = "event: %s\n#{DATA_TEMPL}"
        SSE_HEADER  = {
          STATUS_KEY    => '200',
          :content_type => 'text/event-stream'
        }

        # build and return +EventSource+ instance, ready for pushing out data
        # or named events. checks accept header in the request, then responds
        # with valid headers for beginning an SSE stream
        #
        # @param [H2::Server::Stream] stream: the +Stream+ instance
        # @param [Hash] headers: optional headers to add to the intial response
        #
        # @return [H2::Server::Stream::EventSource]
        #
        def initialize stream:, headers: {}
          @closed  = false
          @stream  = stream
          @parser  = @stream.stream
          @headers = headers

          check_accept_header
          init_response
        end

        # checks accept header in the request and raises a +StreamError+ if not
        # valid for SSE
        #
        def check_accept_header
          accept = @stream.request.headers['accept']
          unless accept == SSE_HEADER[:content_type]
            raise StreamError, "invalid header accept: #{accept}"
          end
        end

        # responds with SSE headers on this stream
        #
        def init_response
          headers = SSE_HEADER.merge @headers
          @parser.headers stringify_headers(headers)
        rescue ::HTTP2::Error::StreamClosed => sc
          @stream.log :warn, "stream closed early by client"
        end

        # send out a named event with the given data
        #
        # this would be handled by `es.addEventListener('name', (msg)=>{})`
        #
        # @param [String] name: the name of the event
        # @param [String] data: data associated with this event
        #
        def event name:, data:
          e = EVENT_TEMPL % [name, data]
          @parser.data e, end_stream: false
        end

        # send out a message with the given data
        #
        # this would be handled by `es.onmessage((msg)=>{})`
        #
        # @param [String] data associated with this event
        #
        def data str
          d = DATA_TEMPL % str
          @parser.data d, end_stream: false
        end

        # emit a final frame on this stream with +end_stream+ flag
        #
        def close
          @parser.data ''
          @closed = true
        end

        # @return [Boolean] true if this stream is closed
        #
        def closed?
          @closed
        end

      end
    end
  end
end
