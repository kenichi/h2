require 'set'

module H2
  class Stream
    include Blockable
    include On

    STREAM_EVENTS = [
      :close,
      :headers,
      :data
    ]

    attr_reader :body, :client, :headers, :parent, :pushes, :stream

    # create a new h2 stream
    #
    # @param [H2::Client] client the +Client+ bind this +Stream+ to
    # @param [HTTP2::Stream] stream protocol library +HTTP2::Stream+ instance
    # @param [Boolean] push true if a push promise stream, false otherwise
    # @param [H2::Stream] parent the parent stream of this, if push promise stream
    #
    # @return [H2::Stream]
    #
    def initialize client:, stream:, push: false, parent: nil
      @body    = ''
      @client  = client
      @closed  = false
      @headers = {}
      @parent  = parent
      @push    = push
      @pushes  = Set.new
      @stream  = stream

      init_blocking
      yield self if block_given?
      bind_events
    end

    # @return [Integer] stream ID
    #
    def id
      @stream.id
    end

    # @return [Boolean] true if response status is 200
    #
    def ok?
      headers[STATUS_KEY] == '200'
    end

    # @return [Boolean] true if this +Stream+ is closed
    #
    def closed?
      @closed
    end

    # @return [Boolean] true if this +Stream+ is a push promise
    #
    def push?
      @push
    end

    # add a push promise +Stream+ to this +Stream+'s list of "child" pushes
    #
    def add_push stream
      @pushes << stream
    end

    # call cancel and unblock this +Stream+
    #
    def cancel!
      @stream.cancel
      unblock!
    end

    # block this stream until unblocked or timeout
    #
    def block! timeout = nil
      @pushes.each {|p| p.block! timeout}
      super
    end

    # @return [Hash] response headers (blocks)
    #
    def headers
      block!
      @headers
    end

    # @return [String] response headers (blocks)
    #
    def body
      block!
      @body
    end

    # binds all stream events to their respective on_ handlers
    #
    def bind_events
      @stream.on(:close) do
        @parent.add_push self if @parent && push?
        @client.last_stream = self
        @closed = true
        unblock!
        on :close
      end

      ah = method :add_headers
      @stream.on :promise_headers, &ah
      @stream.on :headers, &ah

      @stream.on(:data) do |d|
        on :data, d
        @body << d
      end
    end

    # builds +Hash+ from associative array, merges into response headers
    #
    def add_headers h
      h = Hash[h]
      on :headers, h
      @headers.merge! h
      @headers
    end

    # @return [Hash] a simple +Hash+ with +:headers+ and +:body+ keys/values
    #
    def to_h
      { headers: headers, body: body }
    end

  end
end
