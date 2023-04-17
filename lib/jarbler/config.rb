module Jarbler
  class Config
    attr_accessor :jar_name, :includes, :excludes, :port, :jruby_version

    CONFIG_FILE = 'config/jarble.rb'
    # create instence of Config class with defaults or from config file
    # Should be called from rails/ruby root directory
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
      config.define_jruby_version
      config
    end

    def initialize
      @jar_name = File.basename(Dir.pwd) + '.jar'
      @includes = %w(app bin config config.ru db Gemfile Gemfile.lock lib log script vendor tmp)
      @excludes = %w(tmp/cache tmp/pids tmp/sockets vendor/bundle vendor/cache vendor/ruby)
      @port = 8080
      @jruby_version = nil  # determined automatically at runtime
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
        file.write("  # jRuby version to use if not the latest or the version from .ruby-version is used\n")
        file.write("  # config.jruby_version = '9.2.3.0'\n")
        file.write("  # config.jruby_version = #{"'#{jruby_version}'" || 'nil'}\n")
        file.write(" \n")
        file.write("end\n")
      end
    end

    # define jRuby version if not set in config file
    def define_jruby_version
      unless @jruby_version # not defined in config file
        if File.exist?('.ruby-version')
          # read the file RAILS_ROOT/.ruby-version starting from char at position 6 to the end of the line
          self.jruby_version = File.read('.ruby-version')[6..20].strip
          debug "jRuby version from .ruby-version file: #{jruby_version}"
        else
          # no .ruby-version file, use jRuby version of the latest Gem
          # Fetch the gem specification from Rubygems.org
          jruby_jars_line = `gem search jruby-jars`.match(/^jruby-jars \((.*)\)/)
          self.jruby_version = /\((.*?)\)/.match(jruby_jars_line.to_s)[1]
          debug "jRuby version from latest jruby-jars gem: #{jruby_version}"
        end
      end
    end

    def debug(msg)
      puts msg if ENV['DEBUG']
    end

  end
end