module H2
  class Server
    class Stream
      class PushPromise
        include ContentEncoder
        include HeaderStringifier

        GET    = 'GET'
        STATUS = '200'

        attr_reader :content_length, :path, :push_stream

        # build a new +PushPromise+ for the path, with the headers and body given
        #
        def initialize path:, headers: {}, body: nil
          @path = path
          @body = body
          @headers = headers

          @promise_headers = {
            METHOD_KEY    => GET,
            AUTHORITY_KEY => headers.delete(AUTHORITY_KEY),
            PATH_KEY      => @path,
            SCHEME_KEY    => headers.delete(SCHEME_KEY)
          }

          @fsm = FSM.new
        end

        # create a new promise stream from +stream+, send the headers and set
        # +@push_stream+ from the callback
        #
        def make_on stream
          return unless @fsm.state == :init
          @stream  = stream
          @headers = {STATUS_KEY => STATUS}.merge stringify_headers(@headers)

          check_accept_encoding
          @content_length = @body.bytesize.to_s
          @headers.merge! CONTENT_LENGTH_KEY => @content_length

          @stream.stream.promise(@promise_headers, end_headers: false) do |push|
            push.headers @headers
            @push_stream = push
            @push_stream.on(:close){|err| cancel! if err == :cancel}
          end
          @fsm.transition :made
          self
        end

        def keep_async
          @stream.connection.server.async.handle_push_promise self
        end

        # deliver the body for this promise, optionally splicing into +size+ chunks
        #
        def keep size = nil
          return false unless @fsm.state == :made

          if size.nil?
            @push_stream.data @body
          else
            body = @body

            if body.bytesize > size
              body = @body.dup
              while body.bytesize > size
                @push_stream.data body.slice!(0, size), end_stream: false
                yield if block_given?
              end
            else
              yield if block_given?
            end

            @push_stream.data body
          end

          @fsm.transition :kept
          log :info, self
          @stream.on_complete
        end

        def kept?
          @fsm.state == :kept
        end

        def canceled?
          @fsm.state == :canceled
        end

        # cancel this promise, most likely due to a RST_STREAM frame from the
        # client (already in cache, etc...)
        #
        def cancel!
          @fsm.transition :canceled
          @stream.on_complete
        end

        def log level, msg
          Logger.__send__ level, "[stream #{@push_stream.id}] #{msg}"
        end

        def to_s
          request = @stream.request
          %{#{request.addr} "push #{@path} HTTP/2" #{STATUS} #{@content_length}}
        end
        alias to_str to_s

        # simple state machine to guarantee promise process
        #
        class FSM
          include Celluloid::FSM
          default_state :init
          state :init, to: [:canceled, :made]
          state :made, to: [:canceled, :kept]
          state :kept
          state :canceled
        end

      end
    end
  end
end
