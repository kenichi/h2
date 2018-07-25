require File.expand_path '../../../test_helper', __FILE__

class HTTPSTest < H2::WithServerHandlerTest

  def setup
    @certs_dir = Pathname.new File.expand_path '../../../../tmp/certs', __FILE__
    @ca_file = @certs_dir.join('ca.crt').to_s
    require_relative '../../support/create_certs' unless File.exist? @ca_file

    @server_cert = @certs_dir.join("server.crt").read
    @server_key = @certs_dir.join("server.key").read
    @client_cert = @certs_dir.join("client.crt").read
    @client_cert_unsigned = @certs_dir.join("client.unsigned.crt").read
    @client_key = @certs_dir.join("client.key").read
    @tls_opts = { ca_file: @ca_file }
    super
  end

  def with_tls_server handler = nil
    handler ||= proc do |stream|
      stream.respond status: 200
      stream.connection.goaway
    end

    begin
      server = H2::Server::HTTPS.new host: @host, port: @port, cert: @server_cert, key: @server_key do |c|
        c.each_stream &handler
      end
      yield server
    ensure
      server.terminate if server && server.alive?
    end
  end

  def test_accept_tcp_connections
    with_tls_server do
      s = TCPSocket.new @host, @port
      refute s.closed?
      s.close
    end
  end

  def test_accept_tls_1_2_connections
    with_tls_server do
      s = TCPSocket.new @host, @port
      ctx = OpenSSL::SSL::SSLContext.new

      # https://github.com/jruby/jruby-openssl/issues/99
      ctx.__send__((H2.alpn? ? :alpn_protocols= : :npn_protocols=), ['h2']) unless H2.jruby?

      ctx.ca_file = @ca_file
      ctx.ssl_version = :TLSv1_2
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      s = OpenSSL::SSL::SSLSocket.new s, ctx
      s.sync_close = true
      s.hostname = @host
      s.connect
      refute s.closed?
      s.close
    end
  end

  def test_handle_request_and_responses
    ex = nil
    2.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      begin
        assert_equal 'yo', stream.request.headers['hi']
        @valid.tap
      rescue => ex
      ensure
        stream.respond status: 200, body: 'boo'
        stream.connection.goaway
      end
    end

    with_tls_server handler do
      s = H2.get url: @url, headers: {'hi' => 'yo'}, tls: @tls_opts
      assert_equal 'boo', s.body
      @valid.tap
    end

    @valid.verify
    raise ex if ex
  end

  def test_uses_sni_for_ssl_context
    ex = nil
    2.times { @valid.expect :tap, nil }

    sni = {
      'localhost' => {
        :cert => @server_cert,
        :key  => @server_key
      }
    }

    # resolve 'localhost' as H2::Client will bind to that
    #
    host = Socket.getaddrinfo('localhost', @port).first[3]

    begin
      server = H2::Server::HTTPS.new host: host, port: @port, sni: sni do |c|
        c.each_stream do |stream|
          begin
            assert_equal 'yo', stream.request.headers['hi']
            @valid.tap
          rescue => ex
          ensure
            stream.respond status: 200, body: 'boo'
            stream.connection.goaway
          end
        end
      end
      s = H2.get url: "https://localhost:#{@port}/", headers: {'hi' => 'yo'}, tls: @tls_opts
      assert_equal 'boo', s.body
      @valid.tap
    ensure
      server.terminate if server && server.alive?
    end

    @valid.verify
    raise ex if ex
  end

end
