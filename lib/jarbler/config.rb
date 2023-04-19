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
      @includes = %w(app bin config config.ru db Gemfile Gemfile.lock lib log public script vendor tmp)
      @excludes = %w(tmp/cache tmp/pids tmp/sockets vendor/bundle vendor/cache vendor/ruby)
      @port = 8080
      @jruby_version = nil  # determined automatically at runtime
      # execute additional block if given
      yield self if block_given?
    end

    # Generate the template config file based on default values
    def create_config_file
      write_config_file("\
# Name of the generated jar file
# config.jar_name = '#{jar_name}'

# Application directories or files to include in the jar file
# config.includes = #{includes}
# config.includes << 'additional'

# Application directories or files to exclude from the jar file
# config.excludes = #{excludes}
# config.excludes << 'additional'

# The network port used by the application
# config.port = #{port}

# Use certail jRuby version
# if not set (nil) then the version defined in .ruby-version
# if not jRuby version defined here or in .ruby-version then the latest available jRuby version is used
# config.jruby_version = '9.2.3.0'
# config.jruby_version = nil
      ".split("\n"))
    end

    # write a config file with the given lines
    # if the file exists, it is overwritten
    # if the file does not exist, it is created
    # @param [Array] lines is an array of strings
    def write_config_file(lines)
      lines = [lines] unless lines.is_a?(Array)
      FileUtils.mkdir_p('config')
      raise "config file #{CONFIG_FILE} already exists in current directory! Please move file temporary and try again." if File.exist?(CONFIG_FILE)
      File.open(CONFIG_FILE, 'w') do |file|
        file.write("# Jarbler configuration, see https://github.com/rammpeter/jarbler\n")
        file.write("# values in comments are the default values\n")
        file.write("# uncomment and adjust if needed\n")
        file.write(" \n")
        file.write("Jarbler::Config.new do |config|\n")
        lines.each do |line|
          file.write("  #{line}\n")
        end
        file.write("end\n")
      end
      puts "Jarbler: Created config file #{CONFIG_FILE}"
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
          command = "gem search --remote jruby-jars"
          lines = `#{command}`
          raise "Command \"#{command}\" failed with return code #{$?} and output:\n#{lines}" unless $?.success?
          jruby_jars_line = lines.match(/^jruby-jars \((.*)\)/)
          raise "No jruby-jars gem found in rubygems.org!" unless jruby_jars_line
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