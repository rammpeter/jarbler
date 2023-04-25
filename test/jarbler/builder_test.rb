require 'minitest/autorun'
require 'bundler'
require 'bundler/lockfile_generator'
require 'jarbler/builder'
require 'jarbler/config'

class BuilderTest < Minitest::Test
  def setup
    @builder = Jarbler::Builder.new
  end

  def test_exclude_dirs_removed
    in_temp_dir do
      prepare_gemfiles
      Jarbler::Config.new.write_config_file("config.excludes = ['hugo']")
      @builder.build_jar
      config = Jarbler::Config.create
      assert_jar_file("#{Dir.pwd}/#{config.jar_name}", config)
      assert !File.exist?('hugo')
    end
  end

  def test_local_bundle_path_configured
    in_temp_dir do
      prepare_gemfiles
      # TODO: create additional Gem locally
      @builder.build_jar
      # TODO: Check if additional Gem is in jar file
    end
  end

  private
  # Prepare Gemfiles in temporary test dir and install gems
  def prepare_gemfiles
    File.open('Gemfile', 'w') do |file|
      file.write("source 'https://rubygems.org'\n")
      # file.write("gem 'rake'\n")
    end
    Bundler.with_unbundled_env do # No previous setting inherited like Gemfile location
      Bundler.reset! # Reset settings from previous Bundler.with_unbundled_env
      Bundler.setup # Load Gemfile
      definition = Bundler.definition()
      definition.resolve_remotely! # Install any missing gems and update existing gems
      # Write the new Gemfile.lock file
      File.open('Gemfile.lock', 'w') do
      |file| file.write(Bundler::LockfileGenerator.generate(definition))
      end
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
  # @param [String] filepath
  # @param [Jarbler::Config] config
  def assert_jar_file(filepath, config)
    assert File.exist?(filepath)
    assert File.file?(filepath)
    assert File.extname(filepath) == '.jar'
    Dir.mktmpdir do |dir|
      FileUtils.cp(filepath, dir)
      Dir.chdir(dir) do
        assert system("jar -xf #{File.basename(filepath)}")
        # puts `ls -lR`
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
end