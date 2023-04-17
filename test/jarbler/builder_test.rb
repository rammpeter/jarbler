require 'minitest/autorun'
require 'jarbler/builder'
require 'jarbler/config'

class BuilderTest < Minitest::Test
  def setup
    @builder = Jarbler::Builder.new
  end

  def test_exclude_dirs_removed
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        create_config_file(["config.excludes = hugo"])
        File.open('hugo', 'w') do |file|
          file.write("hugo")
        end
        @builder.build_jar
        assert !File.exist?('hugo')
      end
    end
  end

  private
  def create_config_file(lines)
    FileUtils.mkdir_p('config')
    File.open(Jarbler::Config::CONFIG_FILE, 'w') do |file|
      lines.each do |line|
        file.write(line+"\n")
      end
    end
  end

end