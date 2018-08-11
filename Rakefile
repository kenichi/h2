require 'bundler/gem_tasks'
require 'rake/testtask'
require 'fileutils'

task default: :test

Rake::TestTask.new :test => ['test:certs'] do |t|
  t.test_files = FileList['test/**/*_test.rb']
end

namespace :test do

  desc 'run tests via official ruby docker image'
  task :docker, [:tag] do |_,args|
    tag = args.fetch :tag, 'ruby:2.5'

    FileUtils.mkdir_p 'tmp/docker'
    system "docker pull #{tag}"
    system "docker run --rm -v `pwd`:/opt/src/h2 -it #{tag} /bin/sh -c '" +
           "cd /opt/src/h2 && " +
           "bundle install --path tmp/docker && " +
           "bundle exec rake test'"
  end

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
    require File.expand_path('../test/support/create_certs', __FILE__) unless File.exist? ca_file
  end

  task :nginx, [:tag, :ctx] => [:certs] do |_,args|
    tag = args.fetch :tag, 'h2_nginx_http2'
    ctx = args.fetch :ctx, 'test/support/nginx'

    system "docker build -t #{tag} #{ctx}"
    puts "\nstarting nginx with http/2 support"
    puts "using docker context/document root: #{ctx}"
    puts "using TLS certs: tmp/certs/server.*"
    puts "listening at https://localhost:4430/"
    system "docker run --rm -v `pwd`/tmp/certs:/usr/local/nginx/certs -v `pwd`/#{ctx}:/usr/local/nginx/html -p 4430:443 -it #{tag}"
  end

end
