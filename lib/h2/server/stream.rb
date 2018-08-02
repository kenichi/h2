require 'h2/server/stream/event_source'
require 'h2/server/stream/request'
require 'h2/server/stream/response'
require 'h2/server/push_promise'

module H2
  class Server
    class Stream

      # each stream event method is wrapped in a block to call a local instance
      # method of the same name
      #
      STREAM_EVENTS = [
        :active,
        :close,
        :half_close
      ]

      # the above take only the event, the following receive both the event
      # and the data
      #
      STREAM_DATA_EVENTS = [
        :headers,
        :data
      ]

      attr_reader :connection,
                  :push_promises,
                  :request,
                  :response,
                  :stream

      def initialize connection:, stream:
        @closed        = false
        @completed     = false
        @connection    = connection
        @push_promises = Set.new
        @responded     = false
        @stream        = stream

        bind_events
      end

      # write status, headers, and body to +@stream+
      #
      def respond status:, headers: {}, body: ''
        response = Response.new stream: self,
                                status: status,
                                headers: headers,
                                body: body

        if @closed
          log :warn, 'stream closed before response sent'
        else
          log :info, response
          response.respond_on(stream)
          @responded = true
        end
      end

      # create a push promise, send the headers, then queue an asynchronous
      # task on the reactor to deliver the data
      #
      def push_promise *args
        pp = push_promise_for *args
        make_promise pp
        @connection.server.async.handle_push_promise pp
      end

      # create a push promise
      #
      def push_promise_for path:, headers: {}, body: nil
        headers.merge! AUTHORITY_KEY => @request.authority,
                       SCHEME_KEY    => @request.scheme

        PushPromise.new path: path, headers: headers, body: body
      end

      # begin the new push promise stream from this +@stream+ by sending the
      # initial headers frame
      #
      # @see +PushPromise#make_on!+
      # @see +HTTP2::Stream#promise+
      #
      def make_promise p
        p.make_on self
        push_promises << p
        p
      end

      # set or call +@complete+ callback
      #
      def on_complete &block
        return true if @completed
        if block
          @complete = block
        elsif @completed = (@responded and push_promises_complete?)
          @complete[] if Proc === @complete
          true
        else
          false
        end
      end

      # check for push promises completion
      #
      def push_promises_complete?
        @push_promises.empty? or @push_promises.all? {|p| p.kept? or p.canceled?}
      end

      # trigger a GOAWAY frame when this stream is responded to and any/all push
      # promises are complete
      #
      def goaway_on_complete
        on_complete { connection.goaway }
      end

      # logging helper
      #
      def log level, msg
        Logger.__send__ level, "[stream #{@stream.id}] #{msg}"
      end

      # make this stream into an SSE event source
      #
      # raises +StreamError+ if the request's content-type is not valid
      #
      # @return [H2::Server::Stream::EventSource]
      #
      def to_eventsource headers: {}
        EventSource.new stream: self, headers: headers
      end

      protected

      # bind parser events to this instance
      #
      def bind_events
        STREAM_EVENTS.each do |e|
          on = "on_#{e}".to_sym
          @stream.on(e) { __send__ on }
        end
        STREAM_DATA_EVENTS.each do |e|
          on = "on_#{e}".to_sym
          @stream.on(e) { |x| __send__ on, x }
        end
      end

      # called by +@stream+ when this stream is activated
      #
      def on_active
        log :debug, 'active' if H2.verbose?
        @request = H2::Server::Stream::Request.new self
      end

      # called by +@stream+ when this stream is closed
      #
      def on_close
        log :debug, 'close' if H2.verbose?
        on_complete
        @closed = true
      end

      # called by +@stream+ with a +Hash+
      #
      def on_headers h
        incoming_headers = Hash[h]
        log :debug, "headers: #{incoming_headers}" if H2.verbose?
        @request.headers.merge! incoming_headers
      end

      # called by +@stream+ with a +String+ body part
      #
      def on_data d
        log :debug, "data: <<#{d}>>" if H2.verbose?
        @request.body << d
      end

      # called by +@stream+ when body/request is complete, signaling that client
      # is ready for response(s)
      #
      def on_half_close
        log :debug, 'half_close' if H2.verbose?
        connection.server.async.handle_stream self
      end

    end

    class StreamError < StandardError; end
  end
end
