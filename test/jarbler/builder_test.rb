require 'minitest/autorun'
require 'bundler'
require 'bundler/setup'
require 'bundler/installer'
require 'bundler/lockfile_generator'
require 'jarbler/builder'
require 'jarbler/config'
require 'open3'

class BuilderTest < Minitest::Test
  def setup
    debug "##### Starting test #{self.class.name}::#{self.name}"
    debug "Gem.paths.path in setup: #{Gem.paths.path}"
    debug "GEM_PATH in setup: #{ENV['GEM_PATH']}" if ENV['GEM_PATH']
    @builder = Jarbler::Builder.new
  end

  def teardown
    debug "##### End test #{self.class.name}::#{self.name}"
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
          file.write("#!/usr/bin/env ruby\n")
          file.write("puts 'Starting application hugo'\n")
          file.write("puts 'hugo:' + ARGV.inspect\n")
          file.write("begin\n")
          file.write("  puts 'hugo:' + 'require bundler'\n")
          file.write("  require 'bundler'\n")
          file.write("  puts 'hugo:' + 'require Bundler.setup'\n")
          file.write("  Bundler.setup\n")
          file.write("  require 'jarbler/github_gem_test'\n")
          file.write("  puts Jarbler::GithubGemTest.new.check_github_gem_dependency\n")
          file.write("rescue Exception => e\n")
          file.write("  puts 'Exception in test executable hugo'\n")
          file.write("  puts e.message\n")
          file.write("  puts e.backtrace.join(\"\n\")\n")
          file.write("  raise\n")
          file.write("end\n")
        end
        @builder.build_jar
        assert_jar_file(Dir.pwd)
        debug "Now executing the jar file"
        remove_gem_env
        stdout, stderr, status = Open3.capture3("java -jar hugo.jar -c -d")
        restore_gem_env
        debug "After executing the jar file"
        response_match = stdout.lines.select{|s| s == "hugo:[\"-a\", \"-b\", \"-c\", \"-d\"]\n" } # extract the response line from debug output of hugo.jar
        assert !response_match.empty?, "Response should contain the executable params but is:\n#{stdout}\nstderr:\n#{stderr}"
        assert !stdout.lines.select{|s| s == "SUCCESS\n" }.empty?, "Response should contain the line SUCCESS but is:\n#{stdout}\nstderr:\n#{stderr}"
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
  def test_compiled
    if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
      in_temp_dir do
        # Create ruby files for execution in jar file
        File.open('test_outer.rb', 'w') do |file|
          file.write("\
# Add the current directory to the load path
$LOAD_PATH.unshift __dir__
puts 'Before first require LOAD_PATH is ' + $LOAD_PATH.inspect
require 'test_inner'
puts 'test_outer running'
TestInner.new.test_inner
")
        end
        File.open('test_inner.rb', 'w') do |file|
          file.write("\
require 'nokogiri'
class TestInner
  def test_inner
    puts 'test_inner running'
    puts 'In test_inner LOAD_PATH is ' + $LOAD_PATH.inspect
    Nokogiri::XML('<x>Hugo</x>').xpath('//x').each do |x|
      puts x.text
    end
  end
end
")
        end

        Jarbler::Config.new.write_config_file([
                                                "config.compile_ruby_files = true",
                                                "config.excludes_from_compile = ['app_root/config/jarble.rb']",
                                                "config.executable = 'test_outer.rb'",  # Should be transformed to 'test_outer.class'
                                                "config.includes << 'test_outer.rb'",
                                                "config.includes << 'test_inner.rb'"
                                              ])
        with_prepared_gemfile("gem 'nokogiri'") do
          @builder.build_jar
          assert_jar_file(Dir.pwd) do
            assert !File.exist?("app_root/config/jarble.class"), "File app_root/config/jarble.rb should not be compiled"
            assert File.exist?("app_root/config/jarble.rb"), "File app_root/config/jarble.rb should not be compiled"
          end
          ENV['DEBUG'] = 'true'
          ENV.delete('BUNDLE_BIN_PATH')
          ENV.delete('BUNDLE_GEMFILE')
          ENV.delete('BUNDLER_SETUP')
          ENV.delete('BUNDLER_VERSION')
          ENV.delete('GEM_HOME')
          ENV.delete('RUBYLIB')
          ENV.delete('RUBYOPT')
          stdout, stderr, status = Open3.capture3("java -jar #{Jarbler::Config.create.jar_name}")
          # Ensure that the output contains the expected strings
          assert stdout.include?('test_outer running'), "stdout should contain 'test_outer running' but is:\n#{stdout}\nstderr:\n#{stderr}"
          assert stdout.include?('test_inner running'), "stdout should contain 'test_inner running' but is:\n#{stdout}\nstderr:\n#{stderr}"
          assert stdout.include?('Hugo'), "stdout should contain 'Hugo' but is:\n#{stdout}\nstderr:\n#{stderr}"
        end
      end
    else
      skip "test_compiled is executed only with JRuby"
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

  def debug(msg)
    puts msg if ENV['DEBUG']
  end

  # Remove the Gem/bundler/ruby specific environment to get a environment where the jar file can be started clean
  # Gem env can be restored by calling restore_gem_env
  # @return [void]
  def remove_gem_env
    @bufferred_ruby_env = {}
    ENV.to_h.each do |key, value|
      if key['GEM'] || key['BUNDLE'] || key['RUBY']
        @bufferred_ruby_env[key] = value
        ENV.delete(key)
        debug "Temporary removed #{key} from ENV with value #{value}"
      end
    end
  end

  # Restore the Gem specific environment
  def restore_gem_env
    raise "remove_gem_env must be called before restore_gem_env" unless defined?(@bufferred_ruby_env)
    @bufferred_ruby_env.each do |key, value|
      ENV[key] = value
    end
  end
end