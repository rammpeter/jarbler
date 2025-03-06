require 'fileutils'
require 'open3'

class Minitest::Test

  @@log_file_name = 'log/test.log'
  puts "Console output is redirected to #{@@log_file_name}"
  FileUtils.rm_f(@@log_file_name)

  def setup
    # Redirecting output to a log file
    @@log_file = File.open(@@log_file_name, 'a')
    $stdout = @@log_file

    log "##### Starting test #{self.class.name}::#{self.name}"
    debug "Gem.paths.path in setup: #{Gem.paths.path}"
    debug "GEM_PATH in setup: #{ENV['GEM_PATH']}" if ENV['GEM_PATH']

    super
  end

  def teardown
    log "##### End test #{self.class.name}::#{self.name}\n\n"

    # Restore original stdout
    $stdout = STDOUT
    @@log_file.close

    super
  end

  def log(msg)
    @@log_file.puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{msg}"
  end

  def debug(msg)
    log(msg) if ENV['DEBUG']
  end

  def log_and_out(msg)
    log(msg)
    STDOUT.puts message
  end

  # allow assertions failure message to appear in logfile
  # use like: assert_response :success, log_on_failure('should get log file with JWT')
  # @param [String] message
  def log_on_failure(message)
    Proc.new do
      log("Assertion failed: #{message}")
      STDOUT.puts message
    end
  end

  def exec_and_log(command)
    log("Execute by Open3.capture3: #{command}")
    stdout, stderr, status = Open3.capture3(command)
    log("status from Open3.capture3: #{status}")
    log("stdout from Open3.capture3:\n#{stdout}")
    log("stderr from Open3.capture3:\n#{stderr}")
    assert status.success?, log_on_failure("Response status should be success but is:\n#{stdout}\nstderr:\n#{stderr}\nstatus: #{status}")
    return stdout, stderr, status
  end
end