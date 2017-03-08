require 'concurrent'
require 'h2'

module H2
  class Client
    module Concurrent

      module ClassMethods
        def thread_pool
          procs = ::Concurrent.processor_count
          @thread_pool ||= ::Concurrent::ThreadPoolExecutor.new min_threads: 0,
                                                                max_threads: procs,
                                                                max_queue:   procs * 5
        end
      end

      def read maxlen = DEFAULT_MAXLEN
        main = Thread.current
        @reader = self.class.thread_pool.post do
          begin
            _read maxlen
          rescue => e
            main.raise e
          end
        end
      end

    end

    extend H2::Client::Concurrent::ClassMethods
    prepend H2::Client::Concurrent
  end
end

