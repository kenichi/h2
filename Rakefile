require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

Rake::TestTask.new :test => ['test:certs'] do |t|
  t.test_files = FileList['test/**/*_test.rb']
end

namespace :test do

  desc 'send TTIN signal to test process'
  task :ttin do
    pid = `ps -ef | grep -v grep | grep -e 'ruby.*_test\.rb' | awk '{print $2}'`.strip
    if !pid.empty?
      puts "TTIN -> #{pid}"
      Process.kill 'TTIN', Integer(pid)
    end
  end

  task :certs do
    certs_dir = Pathname.new File.expand_path '../tmp/certs', __FILE__
    ca_file = certs_dir.join('ca.crt').to_s
    require_relative 'test/support/create_certs' unless File.exist? ca_file
  end

  task :nginx => [:certs] do
    system "docker build -t h2_nginx_http2 test/support/nginx"
    puts "\nstarting nginx with http/2 support"
    puts "using document root: test/support/nginx/"
    puts "using TLS certs: tmp/certs/server.*"
    puts "listening at https://localhost:4430/"
    system "docker run --rm -v `pwd`/tmp/certs:/usr/local/nginx/certs -v `pwd`/test/support/nginx:/usr/local/nginx/html -p 4430:443 -it h2_nginx_http2"
  end

end
