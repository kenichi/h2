require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

Rake::TestTask.new :test do |t|
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

end
