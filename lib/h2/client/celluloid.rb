require 'celluloid/current'
require 'h2'

module H2
  class Client
    module Celluloid

      class Reader
        include ::Celluloid

        def read client, maxlen = DEFAULT_MAXLEN
          client._read maxlen
        end
      end

      module ClassMethods
        def thread_pool
          @thread_pool ||= Reader.pool
        end
      end

      def read maxlen = DEFAULT_MAXLEN
        self.class.thread_pool.async.read self
      end

    end

    extend H2::Client::Celluloid::ClassMethods
    prepend H2::Client::Celluloid
  end
end
