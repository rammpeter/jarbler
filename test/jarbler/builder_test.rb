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
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        prepare_gemfiles
        Jarbler::Config.new.write_config_file("config.excludes = ['hugo']")
        @builder.build_jar
        assert !File.exist?('hugo')
      end
    end
  end

  private
  # Prepare Gemfiles in temporary test dir and install gems
  def prepare_gemfiles
    File.open('Gemfile', 'w') do |file|
      file.write("source 'https://rubygems.org'\n")
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

end