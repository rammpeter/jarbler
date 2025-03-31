require 'fileutils'
require 'open3'

class Minitest::Test

  def setup
    start_msg = "Starting test #{self.class.name}::#{self.name}"
    puts "\n\n#{'-' * (start_msg.length + 20)}"
    log start_msg
    puts '-' * (start_msg.length + 20)
    debug "Gem.paths.path in setup: #{Gem.paths.path}"
    debug "GEM_HOME in setup: #{ENV['GEM_HOME']}" if ENV['GEM_HOME']
    debug "GEM_PATH in setup: #{ENV['GEM_PATH']}" if ENV['GEM_PATH']

    super
  end

  def teardown
    end_msg = "End of test #{self.class.name}::#{self.name}"
    puts "#{'-' * (end_msg.length + 20)}"
    log end_msg
    puts '-' * (end_msg.length + 20)
    super
  end

  def log(msg)
    puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{msg}"
  end

  def debug(msg)
    log(msg) if ENV['DEBUG']
  end

  # Execute command and log the result
  # @param [String] command command to execute
  # @param [Hash] env environment variables to set for the command
  # @return [Array] stdout, stderr, status
  # @raise [RuntimeError] if the command fails
  def exec_and_log(command, env: {})
    log("Execute by Open3.capture3: #{command}")
    stdout, stderr, status = Open3.capture3(env, command)
    log("Command '#{command}'Executed with  Open3.capture3: status = #{status}\nstdout:\n#{stdout}\n\nstderr:\n#{stderr}\n")
    assert status.success?, "Response status should be success but is '#{status}':\n#{stdout}\nstderr:\n#{stderr}"
    return stdout, stderr, status
  end
end