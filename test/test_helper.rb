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

  # calculate the jruby jar file to use for the current test depending on the installed java version
  # @return [String] the whole line for config entry 'jruby_version'
  def jruby_version_test_config_line
    result = ''
    java_version = `java -version 2>&1`
    major_java_version = java_version.match('version "\K[0-9]+').to_s.to_i
    debug "Minitest::Test.jruby_version_test_config_line: current Java mojor version = #{major_java_version}"

    if major_java_version < 21
      result = "jruby_version = '9.4.12.0'"   # Use a JRuby version that is compatible with Java 8 and 11 etc.
    end
    debug "Minitest::Test.jruby_version_test_config_line: result = #{result}"
    result
  end
end