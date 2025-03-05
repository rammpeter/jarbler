require 'fileutils'
require 'open3'

class Minitest::Test

  @@log_file_name = 'log/test.log'
  puts "Console output is redirected to #{@@log_file_name}"
  FileUtils.rm_f(@@log_file_name)

  def setup
    # Redirecting output to a log file
    @@log_file = File.open(@@log_file_name, 'a')
    @@original_stdout = $stdout
    $stdout = @@log_file

    log "##### Starting test #{self.class.name}::#{self.name}"
    debug "Gem.paths.path in setup: #{Gem.paths.path}"
    debug "GEM_PATH in setup: #{ENV['GEM_PATH']}" if ENV['GEM_PATH']

    super
  end

  def teardown
    log "##### End test #{self.class.name}::#{self.name}\n\n"

    # Restore original stdout
    $stdout = @@original_stdout
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
    @@original_stdout.puts message
  end

  # allow assertions failure message to appear in logfile
  # use like: assert_response :success, log_on_failure('should get log file with JWT')
  # @param [String] message
  def log_on_failure(message)
    Proc.new do
      if $stdout ==  @@original_stdout
        log("Assertion failed: #{message}")
      else
        @@original_stdout.puts message
      end
      message
    end
  end

  def exec_and_log(command)
    log("Execute by Open3.capture3: #{command}")
    $stdout = @@original_stdout     # restore original stdout to prevent external executuion from closed stream error
    stdout, stderr, status = Open3.capture3(command)
    log("status from Open3.capture3: #{status}")
    log("stdout from Open3.capture3:\n#{stdout}")
    log("stderr from Open3.capture3:\n#{stderr}")
    assert status.success?, log_on_failure("Response status should be success but is:\n#{stdout}\nstderr:\n#{stderr}\nstatus: #{status}")
    $stdout = @@log_file  # restore redirect to log file
    return stdout, stderr, status
  end
end