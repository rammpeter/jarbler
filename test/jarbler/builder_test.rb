require 'minitest/autorun'
require 'bundler'
require 'bundler/setup'
require 'bundler/installer'
require 'bundler/lockfile_generator'
require 'jarbler/builder'
require 'jarbler/config'
require 'test_helper'

class BuilderTest < Minitest::Test
  def setup
    @builder = Jarbler::Builder.new
    super
  end

  # Check the right jar file name
  def test_jar_name
    in_temp_dir do
      Jarbler::Config.new.write_config_file("config.jar_name = 'hugo.jar'")
      with_prepared_gemfile do
        @builder.build_jar
        assert File.exist?('hugo.jar'), "Jar file 'hugo.jar' should exist"
        assert_jar_file(Dir.pwd)
      end
    end
  end

  def test_jruby_version
    in_temp_dir do
      with_prepared_gemfile do
        Jarbler::Config.new.write_config_file("config.jruby_version = '9.2.4.0'")
        @builder.build_jar
        assert_jar_file(Dir.pwd) do
          assert File.exist?("jruby-core-9.2.4.0-complete.jar"), "JRuby version core file should exist"
        end
      end
    end
    in_temp_dir do
      with_prepared_gemfile do
        File.open('.ruby-version', 'w') { |file| file.write("jruby-9.2.3.0") }
        @builder.build_jar
        assert_jar_file(Dir.pwd) do
          assert File.exist?("jruby-core-9.2.3.0-complete.jar"), "JRuby version core file should exist"
        end
      end
    end
  end

  def test_executable_and_params
    in_temp_dir do
      with_prepared_gemfile(["gem 'bundler'", "gem 'jarbler_test_github_gem', github: 'rammpeter/jarbler', branch: 'test_github_gem'"]) do
        Jarbler::Config.new.write_config_file("config.jar_name = 'hugo.jar'\nconfig.includes << 'hugo'\nconfig.executable = 'hugo'\nconfig.executable_params = ['-a', '-b']")
        File.open('hugo', 'w') do |file|
          file.write("\
#!/usr/bin/env ruby
puts 'Starting application hugo'
puts 'hugo:' + ARGV.inspect
begin
  puts 'Before first require LOAD_PATH is ' + $LOAD_PATH.inspect
  puts '$DEBUG = ' + $DEBUG.inspect
  puts 'GEM_HOME is ' + ENV['GEM_HOME'].inspect
  puts 'GEM_PATH is ' + ENV['GEM_PATH'].inspect
  puts 'GEM_ROOT is ' + ENV['GEM_ROOT'].inspect

  puts 'hugo:' + 'require bundler'
  require 'bundler'
  puts 'Bundler::VERSION = ' + Bundler::VERSION
  puts 'hugo:' + 'require Bundler.setup'
  Bundler.setup
  require 'jarbler/github_gem_test'
  puts Jarbler::GithubGemTest.new.check_github_gem_dependency
rescue Exception => e
  puts 'Exception in test executable hugo'
  puts e.message
  puts e.backtrace.join(\"\n\")
  raise
end
")
        end
        ENV['DEBUG'] = 'true'
        @builder.build_jar
        assert_jar_file(Dir.pwd)
        stdout, stderr, status = exec_and_log("java -jar hugo.jar -c -d", env: env_to_remove)
        response_match = stdout.lines.select{|s| s == "hugo:[\"-a\", \"-b\", \"-c\", \"-d\"]\n" } # extract the response line from debug output of hugo.jar
        assert !response_match.empty?, "Response should contain the executable params but is:\n#{stdout}\n"
        assert status.success?, "Response status should be success but is '#{status}':\n#{stdout}\nstderr:\n#{stderr}\n"
      end
    end
  end

  def test_exclude_dirs_removed
    in_temp_dir do
      # create the file/dir to exclude
      File.open('hugo', 'w') { |file| file.write("hugo") }
      Jarbler::Config.new.write_config_file("config.excludes = ['hugo']")
      with_prepared_gemfile do
        @builder.build_jar
        assert_jar_file(Dir.pwd)
      end
    end
  end

  def test_excluded_dir_and_file_contained
    in_temp_dir do
      File.open('hugo', 'w') { |file| file.write("hugo") }
      FileUtils.mkdir_p('included')
      File.open('included/hugo', 'w') { |file| file.write("hugo") }
      Jarbler::Config.new.write_config_file("config.includes = ['hugo', 'included']")
      with_prepared_gemfile do
        @builder.build_jar
        assert_jar_file(Dir.pwd) do
          assert File.exist?('app_root/included') &&
                   File.directory?('app_root/included') &&
                   File.exist?('app_root/included/hugo'), "Dir 'included' should be in jar file"
          assert File.exist?('app_root/hugo') , "File 'app_root/hugo' should be in jar file"
        end
      end
    end
  end

  def test_local_bundle_path_configured
    in_temp_dir do
      FileUtils.mkdir_p('.bundle')
      File.open('.bundle/config', 'w') do |file|
        file.write("---\nBUNDLE_PATH: \"vendor/bundle\"\n")
      end
      with_prepared_gemfile(["gem 'minitest'", "gem 'minitest-reporters'"]) do
        @builder.build_jar
        assert_jar_file(Dir.pwd) do # we are in the dir of the extracted jar file
          expected_dir = "gems/*/*/gems/minitest*"
          assert !Dir.glob(expected_dir).empty?, "Dir #{expected_dir} should be in jar file"
        end
      end
    end
  end

  # test if jar file is created of compiled .class files and executes well
  def test_uncompiled_with_gem_dependency
    in_temp_dir do
      # Create ruby files for execution in jar file
      File.open('test.rb', 'w') do |file|
        file.write("\
puts 'Before first require LOAD_PATH is ' + $LOAD_PATH.inspect
puts '$DEBUG = ' + $DEBUG.inspect
puts 'GEM_HOME is ' + ENV['GEM_HOME'].inspect
puts 'GEM_PATH is ' + ENV['GEM_PATH'].inspect
puts 'GEM_ROOT is ' + ENV['GEM_ROOT'].inspect
# Ensure Bundler adds the Gem paths to the LOAD_PATH
require 'bundler'
puts 'Bundler::VERSION = ' + Bundler::VERSION
puts 'hugo:' + 'require Bundler.setup'
Bundler.setup
puts 'After Bundler.setup LOAD_PATH is ' + $LOAD_PATH.inspect

require 'base64'
puts 'After first require LOAD_PATH is ' + $LOAD_PATH.inspect
puts Base64.encode64('Secret')  # Check function of Gem
 ")
      end

      Jarbler::Config.new.write_config_file([
                                              "config.executable = 'test.rb'",
                                              "config.includes << 'test.rb'",
                                            ])
      with_prepared_gemfile("gem 'base64'") do
        @builder.build_jar
        ENV['DEBUG'] = 'true'
        stdout, _stderr, _status = exec_and_log("java -jar #{Jarbler::Config.create.jar_name}", env: env_to_remove)
        # Ensure that the output contains the expected strings
        assert stdout.include?('U2VjcmV0'), "stdout should contain result of Base64.encode64('Secret')  but is:\n#{stdout}\n"
      end
    end
  end


  # test if jar file is created of compiled .class files and executes well
  def test_compiled
    suppress_test = false
    unless defined?(RUBY_ENGINE)
      puts "RUBY_ENGINE not defined, test suppressed"
      suppress_test = true
    end

    if defined?(RUBY_ENGINE) && RUBY_ENGINE != 'jruby'
      puts "RUBY_ENGINE=#{RUBY_ENGINE} is not jruby, test suppressed"
      suppress_test = true
    end

    if defined?(JRUBY_VERSION) && JRUBY_VERSION['SNAPSHOT']
      puts "No jruby-jars expected to be available for JRUBY_VERSION=#{JRUBY_VERSION}, test suppressed"
      suppress_test = true
    end

    unless suppress_test

      in_temp_dir do
        # Create ruby files for execution in jar file
        File.open('test_outer.rb', 'w') do |file|
          file.write("\
# Add the current directory to the load path
$LOAD_PATH.unshift __dir__
puts 'Before first require LOAD_PATH is ' + $LOAD_PATH.inspect
puts 'GEM_HOME is ' + ENV['GEM_HOME'].inspect
puts 'GEM_PATH is ' + ENV['GEM_PATH'].inspect

# Ensure Bundler adds the Gem paths to the LOAD_PATH
require 'bundler'
puts 'Bundler::VERSION = ' + Bundler::VERSION
puts 'hugo:' + 'require Bundler.setup'
Bundler.setup
puts 'After Bundler.setup LOAD_PATH is ' + $LOAD_PATH.inspect

require 'test_inner'
puts 'after require GEM_HOME is ' + ENV['GEM_HOME'].inspect
puts 'after require GEM_PATH is ' + ENV['GEM_PATH'].inspect
puts 'test_outer running'
TestInner.new.test_inner
")
        end
        File.open('test_inner.rb', 'w') do |file|
          file.write("\
require 'base64'
class TestInner
  def test_inner
    puts 'test_inner running'
    puts 'In test_inner LOAD_PATH is ' + $LOAD_PATH.inspect
    puts Base64.encode64('Secret')  # Check function of Gem
   end
end
")
        end
        ENV['DEBUG'] = 'true'
        debug "JRUBY_VERSION: #{JRUBY_VERSION}"
        Jarbler::Config.new.write_config_file([
                                                "config.compile_java_version  = '1.8'",
                                                "config.compile_ruby_files    = true",
                                                "config.excludes_from_compile = ['app_root/config/jarble.rb']",
                                                "config.executable            = 'test_outer.rb'",  # Should be transformed to 'test_outer.class'
                                                "config.includes              << 'test_outer.rb'",
                                                "config.includes              << 'test_inner.rb'",
                                                "config.jruby_version = '#{JRUBY_VERSION}'"   # Should use the current JRuby version for compilation and jar files
                                              ])
        with_prepared_gemfile("gem 'base64'") do
          @builder.build_jar
          assert_jar_file(Dir.pwd) do
            assert !File.exist?("app_root/config/jarble.class"), "File app_root/config/jarble.rb should not be compiled"
            assert File.exist?("app_root/config/jarble.rb"), "File app_root/config/jarble.rb should not be compiled"
          end
          stdout, _stderr, _status = exec_and_log("java -jar #{Jarbler::Config.create.jar_name}", env: env_to_remove)
          # Ensure that the output contains the expected strings
          assert stdout.include?('test_outer running'), "stdout should contain 'test_outer running' but is:\n#{stdout}\n"
          assert stdout.include?('test_inner running'), "stdout should contain 'test_inner running' but is:\n#{stdout}\n"
          assert stdout.include?('U2VjcmV0'), "stdout should contain result of Base64.encode64('Secret')  but is:\n#{stdout}\n"
        end
      end
    else
      skip "test_compiled is executed only with JRuby"
    end
  end

  # This test was for evaluation of https://github.com/jruby/jruby/issues/8680 only
  def test_stripped_env
    File.open('test_env.rb', 'w') do |file|
      file.write("\
        puts 'ENV is '
        ENV.sort.to_h.each do |key, value|
          puts key + ' = ' + value
        end
      ")
    end
    exec_and_log("ruby test_env.rb", env: env_to_remove)
  end

  def test_return_code
    in_temp_dir do
      File.open('test_return_code.rb', 'w') do |file|
        # file.write("raise SystemExit.new(5)")
        file.write("exit 5")
      end

      Jarbler::Config.new.write_config_file([
                                              "config.executable = 'test_return_code.rb'",
                                              "config.includes << 'test_return_code.rb'",
                                            ])
      with_prepared_gemfile do
        @builder.build_jar
        run_env = env_to_remove
        run_env['DEBUG'] = nil                                                  # Should not run in DEBUG mode to ensure that temp dir is removed at exit
        stdout, stderr, status = Open3.capture3(run_env, "java -jar #{Jarbler::Config.create.jar_name}")
        assert status.exitstatus == 5, "status code should be set.\nstdout:\n#{stdout}\nstderr:\n#{stderr}\n"

        # Check if the expansion dir of jar file is removed even if the ruby code terminates with exit
        extract_line = stdout.lines.select{|s| s =~ /Extracting files from / }.first # extract the response line from debug output of jar fir
        # get the content of the string after ' to '
        jar_tmp_dir = extract_line[extract_line.index(' to ')+4, extract_line.length].strip
        if Dir.exist?(jar_tmp_dir)        # This can happen in Windows if the JRuby jar files are not freed from class loader
          Dir.entries(jar_tmp_dir).each  do |entry|
            assert entry == '.' || entry.end_with?('.jar'), "'#{jar_tmp_dir}' should not have other content than .jar but is '#{entry}'"
          end
        end
      end
    end
  end

  private
  # Prepare Gemfiles in temporary test dir and install gems
  # @param additional_gem_file_lines [Array<String>] additional gemfile lines
  def with_prepared_gemfile(additional_gem_file_lines = [])
    additional_gem_file_lines = [additional_gem_file_lines] unless additional_gem_file_lines.is_a?(Array) # Convert to array if not already
    File.open('Gemfile', 'w') do |file|
      file.write("source 'https://rubygems.org'\n")
      additional_gem_file_lines.each do |gem_file_line|
        file.write("#{gem_file_line}\n")
      end
    end
    Bundler.with_unbundled_env do # No previous setting inherited like Gemfile location
      Bundler.reset! # Reset settings from previous Bundler.with_unbundled_env
      debug "Gem path afterBundler.reset! : #{Gem.paths.path}"
      definition = Bundler.definition
      definition.resolve_remotely! # Resolve remote dependencies for Gemfile.lock
      # Write the new Gemfile.lock file
      File.open('Gemfile.lock', 'w') do |file|
        file.write(Bundler::LockfileGenerator.generate(definition))
      end
      Bundler::Installer.install(Dir.pwd, definition) # Install missing Gems from Gemfile

      # Check if the Gem paths of the installed Gems are already in the Gem.paths.path
      definition = Bundler.definition   # Read the definition again after installing missing Gems
      gem_paths = []
      definition.specs.each do |spec|
        gem_paths << File.expand_path("../..", spec.full_gem_path) if spec.name != 'bundler'
      end

      gem_paths.uniq.each do |gem_path|
        unless Gem.paths.path.include?(gem_path)
          Gem.paths.path << gem_path
          debug "Added missing gem path #{gem_path} to Gem.paths.path"
        end
      end
      debug "Gem.paths.path after Bundler::Installer.install: #{Gem.paths.path}"
      yield if block_given?
    end
  end

  # Prepare existing config file in test dir
  def create_config_file(lines)
    FileUtils.mkdir_p('config')
    File.open(Jarbler::Config::CONFIG_FILE, 'w') do |file|
      lines.each do |line|
        file.write(line+"\n")
      end
    end
  end

  # Check if jar file exists and contains the expected files
  # @param [String] app_root Path to original application root directory
  # @return [void]
  def assert_jar_file(app_root)
    config = Jarbler::Config.create
    jar_filepath = "#{app_root}/#{config.jar_name}"

    assert File.exist?(jar_filepath)
    assert File.file?(jar_filepath)
    assert File.extname(jar_filepath) == '.jar'
    Dir.mktmpdir do |dir|
      FileUtils.cp(jar_filepath, dir)
      Dir.chdir(dir) do             # Change to empty temp dir to extract jar file
        assert system("jar -xf #{File.basename(jar_filepath)}")

        # Ensure that excluded files are not in jar file in folder app_root
        config.excludes.each do |exclude|
          assert !File.exist?("app_root/#{exclude}"), "File app_root/#{exclude} should not be in jar file"
        end

        # Ensure that included files are in jar file if they exist in original app root
        config.includes.each do |include|
          if File.exist?("#{app_root}/#{include}")  # File exists in original source
            if config.compile_ruby_files && File.extname(include) == '.rb'
              class_file = include.sub(/\.rb$/, '.class')
              assert File.exist?("app_root/#{class_file}"), "File app_root/#{class_file} should be in jar file"
            else
              assert File.exist?("app_root/#{include}"), "File app_root/#{include} should be in jar file"
            end
          end
        end
        yield if block_given?
      end
    end
  end

  # Execute the block in temporary directory
  def in_temp_dir
    current_dir = Dir.pwd
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        yield
      end
    end
    Dir.chdir(current_dir)
  end

  # remove the environment variables that should not be set for called commands
  # @return [Hash] The environment variables to remove
  def env_to_remove
    result = {}
    ENV.to_h.each do |key, value|
      if key['GEM'] || key['BUNDLE'] || key['RUBY']
        result[key] = nil
        debug "Env. removed for following call #{key} = '#{value}'"
      end
    end
    result
  end
end