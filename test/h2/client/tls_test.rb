require File.expand_path '../../../test_helper', __FILE__

class H2::Client::TLSTest < Minitest::Test

  def create_ssl_context
    ctx             = OpenSSL::SSL::SSLContext.new
    ctx.ssl_version = :TLSv1_2

    unless H2.jruby?
      if H2.alpn?
        ctx.alpn_protocols = ['h2']
        ctx.alpn_select_cb = ->(ps){ ps.find { |p| 'h2' == p }}
      else
        ctx.npn_protocols = ['h2']
        ctx.npn_select_cb = ->(ps){ ps.find { |p| 'h2' == p }}
      end
    end

    ctx
  end

  def test_servname_not_set_when_ipv4_addr
    flag = true
    ctx = create_ssl_context
    ctx.servername_cb = ->(_){ flag = false }
    tcp_server = TCPServer.new '127.0.0.1', 45670
    server = OpenSSL::SSL::SSLServer.new tcp_server, ctx
    st = Thread.new { c = server.accept rescue nil }
    H2::Client.new host: '127.0.0.1', port: 45670 rescue nil
    server.close
    assert flag, 'servername_cb should not have been called!'
  end

  unless ENV['TRAVIS'] == 'true'
    def test_servname_not_set_when_ipv6_addr
      flag = true
      ctx = create_ssl_context
      ctx.servername_cb = ->(_){ flag = false }
      tcp_server = TCPServer.new '::1', 45670
      server = OpenSSL::SSL::SSLServer.new tcp_server, ctx
      st = Thread.new { c = server.accept rescue nil }
      H2::Client.new host: '::1', port: 45670 rescue nil
      server.close
      assert flag, 'servername_cb should not have been called!'
    end
  end

end
