# frozen_string_literal: true

require 'http/2'
require 'logger'
require 'uri'
require 'h2/version'

module H2

  # http/2 psuedo-headers
  #
  AUTHORITY_KEY = ':authority'
  METHOD_KEY    = ':method'
  PATH_KEY      = ':path'
  SCHEME_KEY    = ':scheme'
  STATUS_KEY    = ':status'

  USER_AGENT = {
    'user-agent' => "h2/#{H2::VERSION} #{RUBY_ENGINE}-#{RUBY_VERSION}/#{RUBY_PLATFORM}"
  }

  REQUEST_METHODS = [
    :get,
    :delete,
    :head,
    :options,
    :patch,
    :post,
    :put
  ]

  Logger = ::Logger.new STDOUT

  class << self

    # turn on extra verbose debug logging
    #
    def verbose!
      @verbose = true
    end

    def verbose?
      @verbose = false unless defined?(@verbose)
      @verbose
    end

    # convenience wrappers to make requests with HTTP methods
    #
    # @see H2.request
    #
    REQUEST_METHODS.each do |m|
      define_method m do |**args, &block|
        request method: m, **args, &block
      end
    end

    private

    # creates a +H2::Client+ and initiates a +H2::Stream+ by making a request
    # with the given HTTP method
    #
    # @param [String] host IP address or hostname
    # @param [Integer] port TCP port
    # @param [String,URI] url full URL to parse (optional: existing +URI+ instance)
    # @param [Symbol] method HTTP request method
    # @param [String] path request path
    # @param [Hash] headers request headers
    # @param [Hash] params request query string parameters
    # @param [String] body request body
    # @param [Hash,FalseClass] tls TLS options (optional: +false+ do not use TLS)
    # @option tls [String] :cafile path to CA file
    #
    # @yield [H2::Stream]
    #
    # @return [H2::Stream]
    #
    def request host: nil,
                port: nil,
                url: nil,
                method:,
                path: '/',
                headers: {},
                params: {},
                body: nil,
                tls: {},
                &block

      raise ArgumentError if url.nil? && (host.nil? || port.nil?)
      if url
        url = URI.parse url unless URI === url
        host = url.host
        port = url.port
        path = url.request_uri
      end
      c = Client.new host: host, port: port, tls: tls
      c.__send__ method, path: path, headers: headers, params: params, body: body, &block
    end
  end

  module Blockable

    def init_blocking
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def block! timeout = nil
      @mutex.synchronize { @condition.wait @mutex, timeout } if @condition
    end

    def unblock!
      return unless @condition
      @mutex.synchronize do
        @condition.broadcast
        @condition = nil
      end
    end

  end

  module On

    def on event, *args, &block
      @on ||= {}
      event_handler = @on[event]
      if block_given?
        @on[event] = block
        self
      else
        return if event_handler.nil?
        return event_handler.call(*args)
      end
    end

  end

  module FrameDebugger

    def self.included base
      H2.verbose!
      base::PARSER_EVENTS.push :frame_sent, :frame_received
    end

    def on_frame_sent f
      Logger.debug "Sent frame: #{truncate_frame(f).inspect}"
    end

    def on_frame_received f
      Logger.debug "Received frame: #{truncate_frame(f).inspect}"
    end

    private

    def truncate_string s
      (String === s && s.length > 64) ? "#{s[0,64]}..." : s
    end

    def truncate_frame f
      f.reduce({}) { |h, (k, v)| h[k] = truncate_string(v); h }
    end

  end

  module HeaderStringifier

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

require 'h2/client'
require 'h2/stream'
