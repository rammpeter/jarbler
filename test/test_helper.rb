require 'fileutils'
require 'open3'

class Minitest::Test

  def setup
    puts "\n\n-------------------------------------------------------------------"
    log "##### Starting test #{self.class.name}::#{self.name}"
    debug "Gem.paths.path in setup: #{Gem.paths.path}"
    debug "GEM_HOME in setup: #{ENV['GEM_HOME']}" if ENV['GEM_HOME']
    debug "GEM_PATH in setup: #{ENV['GEM_PATH']}" if ENV['GEM_PATH']

    super
  end

  def teardown
    log "##### End test #{self.class.name}::#{self.name}\n\n"
    super
  end

  def log(msg)
    puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{msg}"
  end

  def debug(msg)
    log(msg) if ENV['DEBUG']
  end

  def exec_and_log(command)
    log("Execute by Open3.capture3: #{command}")
    stdout, stderr, status = Open3.capture3(command)
    log("Command '#{command}'Executed with  Open3.capture3: status = #{status}\nstdout:\n#{stdout}\n\nstderr:\n#{stderr}\n")
    assert status.success?, "Response status should be success but is:\n#{stdout}\nstderr:\n#{stderr}\nstatus: #{status}"
    return stdout, stderr, status
  end
end