module H2
  VERSION = '0.6.1'

  class << self

    ALPN_OPENSSL_MIN_VERSION = 0x10002001

    def alpn?
      exceptionless_io? && OpenSSL::OPENSSL_VERSION_NUMBER >= ALPN_OPENSSL_MIN_VERSION
    end

    def exceptionless_io?
      RUBY_VERSION >= '2.3' && !jruby?
    end

    def jruby?
      return @jruby if defined? @jruby
      @jruby = RUBY_ENGINE == 'jruby'
    end

  end

end
