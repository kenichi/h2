require 'reel/connection'
require 'reel/request'
require 'reel/server'

# see also: https://github.com/celluloid/reel/pull/228


# this is a little sneaky, not as direct as the PR above, but the least
# invasive way i could come up with to get access to the server from the
# request.

module Reel

  # we add a `server` accessor to +Connection+...
  #
  class Request
    attr_reader :connection
  end

  # ... and a `connection` reader to +Request+.
  #
  class Connection
    attr_accessor :server
  end

end

module H2
  module Reel
    module ServerConnection

      # then we hijack +Server+ construction, and wrap the callback at the last
      # minute with one that sets the server on every connection, before
      # calling the original.
      #
      def initialize server, options = {}, &callback
        super
        @og_callback = @callback
        @callback = ->(conn) {
          conn.server = self
          @og_callback[conn]
        }
      end
    end

    ::Reel::Server.prepend ServerConnection
  end
end
