require 'rubygems'
require 'json'

module Jarbler
  class Config
    attr_accessor :jar_name, :includes, :excludes, :jruby_version, :executable, :executable_params, :compile_ruby_files, :include_gems_to_compile, :excludes_from_compile

    CONFIG_FILE = 'config/jarble.rb'
    # create instance of Config class with defaults or from config file
    # Should be called from rails/ruby root directory
    def self.create
      if File.exist?(CONFIG_FILE)
        config = eval(File.read(CONFIG_FILE), binding, CONFIG_FILE, 0)
      else
        config = Jarbler::Config.new
      end
      unless config.class == Jarbler::Config
        Jarbler.debug "No valid config provided in #{CONFIG_FILE}! Using defaults."
        config = Config.new
      end
      config.define_jruby_version
      # Replace .rb with .class if compile_ruby_files is true
      config.executable = config.executable.sub(/\.rb$/, '.class') if config.compile_ruby_files

      config.validate_values
      config
    end

    def initialize
      @compile_ruby_files = false
      @excludes = %w(tmp/cache tmp/pids tmp/sockets vendor/bundle vendor/cache vendor/ruby)
      @excludes_from_compile = %w(config)
      @executable = 'bin/rails'
      @executable_params = %w(server -e production -p 8080)
      @include_gems_to_compile = false
      @includes = %w(app bin config config.ru db Gemfile Gemfile.lock lib log public Rakefile script vendor tmp)
      @jar_name = File.basename(Dir.pwd) + '.jar'
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

# Use certain JRuby version
# if not set (nil) then the version defined in .ruby-version
# if not JRuby version defined here or in .ruby-version then the latest available JRuby version is used
# config.jruby_version = '9.2.3.0'
# config.jruby_version = nil

# The Ruby executable file to run, e.g. 'bin/rails' or 'bin/rake'
# config.executable = '#{executable}'

# Additional command line parameters for the Ruby executable
# config.executable_params = #{executable_params}

# Compile the ruby files of the project to Java .class files with JRuby's ahead-of-time compiler?
# the original ruby files are not included in the jar file, so source code is not visible
# config.compile_ruby_files = #{compile_ruby_files}

# Compile also the .rb files of the gems of the project to Java .class files?
# config.include_gems_to_compile = #{include_gems_to_compile}

# Directories or files to exclude from the compilation if compile_ruby_files = true
# config.excludes_from_compile = #{excludes_from_compile}

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
      puts "Jarbler: Created config file #{Dir.pwd}/#{CONFIG_FILE}"
    end

    # define JRuby version if not set in config file
    def define_jruby_version
      unless @jruby_version # not defined in config file
        if File.exist?('.ruby-version')
          # read the file RAILS_ROOT/.ruby-version starting from char at position 6 to the end of the line
          self.jruby_version = File.read('.ruby-version')[6..20].strip
          debug "JRuby version from .ruby-version file: #{jruby_version}"
        else
          # no .ruby-version file, use JRuby version of the latest Gem
          # Fetch the gem specification from Rubygems.org
          # search for the gem and get the JSON response
          response = Gem::SpecFetcher.fetcher.search_for_dependency(Gem::Dependency.new('jruby-jars'))
          # extract the versions from the response
          self.jruby_version = response&.first&.first&.first&.version&.to_s
          raise "Unable to determine the latest available version of jruby-jars gem!\Rsponse = #{response.inspect}" unless self.jruby_version

          #command = "gem search --remote jruby-jars"
          #lines = `#{command}`
          #raise "Command \"#{command}\" failed with return code #{$?} and output:\n#{lines}" unless $?.success?
          #jruby_jars_line = lines.match(/^jruby-jars \((.*)\)/)
          #raise "No jruby-jars gem found in rubygems.org!" unless jruby_jars_line
          #self.jruby_version = /\((.*?)\)/.match(jruby_jars_line.to_s)[1]
          debug "JRuby version from latest jruby-jars gem: #{jruby_version}"
        end
      end
    end

    def debug(msg)
      puts msg if ENV['DEBUG']
    end

    def validate_values
      raise "Invalid config value for jar name: #{jar_name}" unless jar_name =~ /\w+/
      raise "Invalid config value for executable: #{executable}" unless executable =~ /\w+/
      raise "Invalid config value for executable params: #{executable_params}" unless executable_params.is_a?(Array)
      raise "Invalid config value for includes: #{includes}" unless includes.is_a?(Array)
      raise "Invalid config value for excludes: #{excludes}" unless excludes.is_a?(Array)
      raise "Invalid config value for compile_ruby_files: #{compile_ruby_files}" unless [true, false].include?(compile_ruby_files)
      raise "compile_ruby_files = true is supported only with JRuby! Current runtime is '#{RUBY_ENGINE}'" if compile_ruby_files && (defined?(RUBY_ENGINE) && RUBY_ENGINE != 'jruby')
      raise "include_gems_to_compile = true is supported only if compile_ruby_files = true!" if include_gems_to_compile && !compile_ruby_files
      raise "Invalid config value for excludes_from_compile: #{excludes_from_compile}" unless excludes_from_compile.is_a?(Array)
    end
  end
end