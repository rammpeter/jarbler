module Jarbler
  class Config
    attr_accessor :jar_name, :includes, :excludes, :port

    CONFIG_FILE = 'config/jarble.rb'
    def self.create
      if File.exists?(CONFIG_FILE)
        config = eval(File.read(CONFIG_FILE), binding, CONFIG_FILE, 0)
      else
        config = Jarbler::Config.new
      end
      unless config.class == Jarbler::Config
        Jarbler.debug "No valid config provided in #{CONFIG_FILE}! Using defaults."
        config = Config.new
      end
      config
    end

    def initialize
      @jar_name = File.basename(Dir.pwd) + '.jar'
      @dirs = %w(app bin config db Gemfile Gemfile.lock lib log script vendor tmp)
      @includes = %w(app bin config config.ru db Gemfile Gemfile.lock lib log script vendor tmp)
      @excludes = []
      @port = 8080
      # execute additional block if given
      yield self if block_given?
    end

    def create_config_file
      raise "No config subdir in current directory" unless File.exist?('config') && File.directory?('config')
      raise "config file #{CONFIG_FILE} already exists in current directory" if File.exist?(CONFIG_FILE)
      File.open(CONFIG_FILE, 'w') do |file|
        file.write("# Jarbler configuration, see https://github.com/rammpeter/jarbler\n")
        file.write("# values in comments are the default values\n")
        file.write("# uncomment and adjust if needed\n")
        file.write(" \n")
        file.write("Jarbler::Config.new do |config|\n")
        file.write("  # Name of the generated jar file \n")
        file.write("  # config.jar_name = '#{jar_name}'\n")
        file.write(" \n")
        file.write("  # Application directories or files to include in the jar file\n")
        file.write("  # config.includes = #{includes}\n")
        file.write(" \n")
        file.write("  # Application directories or files to exclude from the jar file\n")
        file.write("  # config.excludes = #{excludes}\n")
        file.write(" \n")
        file.write("  # The network port used by the application\n")
        file.write("  # config.port = #{port}\n")
        file.write(" \n")
        file.write("end\n")
      end
    end

  end
end