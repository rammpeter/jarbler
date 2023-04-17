require 'minitest/autorun'
require 'jarbler/config'

class ConfigTest < Minitest::Test
  def setup
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
        assert_equal @config.port, 8080
      end
    end
  end

  def test_create_with_config_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('config')
        File.open(Jarbler::Config::CONFIG_FILE, 'w') do |file|
          file.write("Jarbler::Config.new do |config|\n")
          file.write("  config.jar_name = 'Modified.jar'\n")
          file.write("  config.includes = ['modified']\n")
          file.write("  config.excludes = ['modified']\n")
          file.write("  config.port = 4040\n")
          file.write("end\n")
        end
        config = Jarbler::Config.create
        assert_equal config.jar_name, 'Modified.jar'
        assert_equal config.includes, ['modified']
        assert_equal config.excludes, ['modified']
        assert_equal config.port, 4040
      end
    end
  end
  def test_create_config_file
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('config')
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
        # Test value from config file
        FileUtils.mkdir_p('config')
        File.open(Jarbler::Config::CONFIG_FILE, 'w') do |file|
          file.write("Jarbler::Config.new do |config|\n")
          file.write("  config.jruby_version = '3.3.3.0'\n")
          file.write("end\n")
        end
        config = Jarbler::Config.create
        assert_equal config.jruby_version, '3.3.3.0'
      end
    end
  end

end