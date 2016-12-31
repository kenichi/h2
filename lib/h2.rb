# frozen_string_literal: true

require 'http/2'
require 'uri'

module H2

  # http/2 psuedo-headers
  #
  AUTHORITY_KEY = ':authority'
  METHOD_KEY    = ':method'
  PATH_KEY      = ':path'
  SCHEME_KEY    = ':scheme'
  STATUS_KEY    = ':status'

  REQUEST_METHODS = [
    :get,
    :delete,
    :head,
    :options,
    :patch,
    :post,
    :put
  ]

  class << self

    REQUEST_METHODS.each do |m|
      define_method m do |**args, &block|
        request method: m, **args, &block
      end
    end

    private

    def request addr: nil,
                port: nil,
                method:,
                path: '/',
                headers: {},
                params: {},
                body: nil,
                url: nil,
                tls: {},
                &block

      raise ArgumentError if url.nil? && (addr.nil? || port.nil?)
      if url
        url = URI.parse url unless URI === url
        addr = url.host
        port = url.port
        path = url.request_uri
      end
      c = Client.new addr: addr, port: port, tls: tls
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
      return @on[event]&.call(*args) unless block_given?
      return @on[event] = block if block_given?
      self
    end

  end

end

require 'h2/client'
require 'h2/stream'
require 'h2/version'
