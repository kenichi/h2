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

    def id
      @stream.id
    end

    def ok?
      headers[STATUS_KEY] == '200'
    end

    def closed?
      @closed
    end

    def push?
      @push
    end

    def add_push stream
      @pushes << stream
    end

    def cancel!
      @stream.cancel
      unblock!
    end

    def block! timeout = nil
      @pushes.each {|p| p.block! timeout}
      super
    end

    def headers
      block!
      @headers
    end

    def body
      block!
      @body
    end

    def bind_events
      @stream.on(:close) do
        @parent.add_push self if @parent && push?
        @client.last_stream = self
        @closed = true
        unblock!
        on :close
      end

      @stream.on(:headers) do |h|
        h = Hash[h]
        on :headers, h
        @headers.merge! h
      end

      @stream.on(:data) do |d|
        on :data, d
        @body << d
      end
    end

    def to_h
      { headers: headers, body: body }
    end

  end
end
