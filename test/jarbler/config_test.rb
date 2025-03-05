require 'minitest/autorun'
require 'jarbler/config'
require 'test_helper'

class ConfigTest < Minitest::Test
  def setup
    super
    @config = Jarbler::Config.new
  end

  def test_config_file_name
    assert_equal 'config/jarble.rb', Jarbler::Config::CONFIG_FILE
  end

  def test_create_without_config_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @config = Jarbler::Config.new
        assert_equal @config.jar_name, File.basename(Dir.pwd) + '.jar'
        assert_equal @config.includes, Jarbler::Config.new.includes
        assert_equal @config.excludes, Jarbler::Config.new.excludes
      end
    end
  end

  def test_create_with_config_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        Jarbler::Config.new.write_config_file("\
          config.jar_name = 'Modified.jar'
          config.includes = ['modified']
          config.excludes = ['modified']
        ")

        config = Jarbler::Config.create
        assert_equal config.jar_name, 'Modified.jar'
        assert_equal config.includes, ['modified']
        assert_equal config.excludes, ['modified']
      end
    end
  end
  def test_create_config_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @config.create_config_file
        assert File.exist?(Jarbler::Config::CONFIG_FILE)
      end
    end
  end

  def test_define_jruby_version
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Test value from rubygems.org
        config = Jarbler::Config.create
        assert config.jruby_version =~ /\d+\.\d+\.\d+\.\d+/
        latest_jruby_version =  config.jruby_version                           # remember for later tests
        # Test value from config file
        Jarbler::Config.new.write_config_file("config.jruby_version = '3.3.3.0'")
        config = Jarbler::Config.create
        assert_equal config.jruby_version, '3.3.3.0'
        File.delete(Jarbler::Config::CONFIG_FILE)

        # Test value from .ruby-version
        File.write('.ruby-version', 'jruby-9.2.4.0')
        config = Jarbler::Config.create
        assert_equal config.jruby_version, '9.2.4.0'

        # Test value from .ruby-version is not a jruby version
        File.write('.ruby-version', 'ruby-3.5.0')
        config = Jarbler::Config.create
        assert_equal config.jruby_version, latest_jruby_version

        # Test value from .ruby-version is not a valid jruby version
        File.write('.ruby-version', 'jruby-3.5.0')
        config = Jarbler::Config.create
        assert_equal config.jruby_version, latest_jruby_version

      end
    end
  end

  def test_deprecated_attributes
    @config.include_gems_to_compile = true  # deprecated attribute should not raise an error if used in config file
  end

end