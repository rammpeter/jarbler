require 'minitest/autorun'
require 'bundler'
require 'bundler/setup'
require 'bundler/installer'
require 'bundler/lockfile_generator'
require 'jarbler/builder'
require 'jarbler/config'

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

  def test_exclude_dirs_removed
    in_temp_dir do
      # create the file/dir to exclude
      File.open('hugo', 'w') do |file|
        file.write("hugo")
      end
      Jarbler::Config.new.write_config_file("config.excludes = ['hugo']")
      with_prepared_gemfile do
        @builder.build_jar
        assert_jar_file(Dir.pwd)
      end
    end
  end

  def test_local_bundle_path_configured
    in_temp_dir do
      FileUtils.mkdir_p('.bundle')
      File.open('.bundle/config', 'w') do |file|
        file.write("---\nBUNDLE_PATH: \"vendor/bundle\"\n")
      end
      with_prepared_gemfile('minitest') do
        @builder.build_jar
        assert_jar_file(Dir.pwd)
      end
      # TODO: Check if additional Gem is in jar file
    end
  end

  private
  # Prepare Gemfiles in temporary test dir and install gems
  def with_prepared_gemfile(additional_gems = [])
    additional_gems = [additional_gems] unless additional_gems.is_a?(Array) # Convert to array if not already
    File.open('Gemfile', 'w') do |file|
      file.write("source 'https://rubygems.org'\n")
      additional_gems.each do |gem|
        file.write("gem '#{gem}'\n")
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

        # Ensure that excluded files are not in jar file
        config.excludes.each do |exclude|
          assert !File.exist?(exclude), "File #{exclude} should not be in jar file"
        end

        # Ensure that included files are in jar file if they exist in original app root
        config.includes.each do |include|
          if File.exist?("#{app_root}/include")
            assert File.exist?(include), "File #{include} should be in jar file"
          end
        end
      end
    end
  end

  # Execute the block in temporary directory
  def in_temp_dir
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        yield
      end
    end
  end

  def debug(msg)
    puts msg if ENV['DEBUG']
  end
end