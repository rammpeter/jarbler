require 'rubygems'
require 'json'

module Jarbler
  class Config
    attr_accessor :compile_java_version,            # compile_java_version only for backward compatibility, use java_opts instead
                  :compile_ruby_files,
                  :excludes,
                  :excludes_from_compile,
                  :executable,
                  :executable_params,
                  :includes,
                  :java_opts,
                  :jar_name,
                  :jrubyc_opts,
                  :jruby_version

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
      config.executable = config.executable.sub(/\.rb$/, '.class') if config.compile_ruby_files && !config.excludes_from_compile.include?("app_root#{File::SEPARATOR}#{config.executable}")

      config.validate_values

      puts ""
      if File.exist?(CONFIG_FILE)
        puts "Configuration loaded from file #{File.join(Dir.pwd, CONFIG_FILE)}"
      else
        puts "No configuration file found at #{File.join(Dir.pwd, CONFIG_FILE)}. Using default values."
      end
      puts "Used configuration values are:"
      puts "  compile_ruby_files:       #{config.compile_ruby_files}"
      puts "  excludes:                 #{config.excludes}"
      puts "  excludes_from_compile:    #{config.excludes_from_compile}" if config.compile_ruby_files
      puts "  executable:               #{config.executable}"
      puts "  executable_params:        #{config.executable_params}"
      puts "  includes:                 #{config.includes}"
      puts "  jar_name:                 #{config.jar_name}"
      puts "  java_opts:                #{config.java_opts}"
      puts "  jrubyc_opts:              #{config.jruby_version}" if config.compile_ruby_files
      puts "  jruby_version:            #{config.jruby_version}"
      puts ""
      config
    end

    def initialize
      @compile_ruby_files = false
      @compile_java_version = nil                                               # deprecated, use java_opts instead
      @excludes = %w(tmp/cache tmp/pids tmp/sockets vendor/bundle vendor/cache vendor/ruby)
      @excludes_from_compile = []
      @executable = 'bin/rails'
      @executable_params = %w(server -e production -p 8080)
      @includes = %w(app bin config config.ru db Gemfile Gemfile.lock lib log public Rakefile script vendor tmp)
      @java_opts = nil
      @jar_name = File.basename(Dir.pwd) + '.jar'
      @jrubyc_opts = []
      @jruby_version = nil  # determined automatically at runtime
      # execute additional block if given
      yield self if block_given?
    end

    # Generate the template config file based on default values
    def create_config_file
      write_config_file("\
# Compile the ruby files of the project to Java .class files with JRuby's ahead-of-time compiler?
# the original ruby files are not included in the jar file, so source code is not visible
# config.compile_ruby_files = #{compile_ruby_files}

# Application directories or files to exclude from the jar file
# config.excludes = #{excludes}
# config.excludes << 'additional'

# Directories or files to exclude from the compilation if compile_ruby_files = true
# The paths map to the final location of files or dirs in the jar file, e.g. config.excludes_from_compile = ['gems', 'app_root/app/models']
# config.excludes_from_compile = #{excludes_from_compile}

# The Ruby executable file to run, e.g. 'bin/rails' or 'bin/rake'
# config.executable = '#{executable}'

# Additional command line parameters for the Ruby executable
# config.executable_params = #{executable_params}

# Application directories or files to include in the jar file
# config.includes = #{includes}
# config.includes << 'additional'

# Name of the generated jar file
# config.jar_name = '#{jar_name}'

# Additional options for the Java compiler (javac).
# Used for the compilation of the jar file bootstrap class JarMain.java.
# Also used for the optional compilation of the ruby files if compile_ruby_files = true.
# E.g. control the class file version of the generated jar file with -source and -target
# config.java_opts = '-target 1.8 -source 1.8'

# Additional options for the JRuby compiler (jrubyc).
# Used for the optional compilation of the ruby files if compile_ruby_files = true.
# config.jrubyc_opts = ['--javac'. '--verbose']

# Use certain JRuby version
# if not set (nil) then the version defined in .ruby-version
# if not JRuby version defined here or in .ruby-version then the latest available JRuby version is used
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
      puts "Jarbler: Created config file #{Dir.pwd}/#{CONFIG_FILE}"
    end

    # define JRuby version if not set in config file
    def define_jruby_version
      if @jruby_version.nil? && File.exist?('.ruby-version')                    # not yet defined in config file but .ruby-version file exists
        # read the file RAILS_ROOT/.ruby-version starting from char at position 6 to the end of the line
        full_jruby_version_string = File.read('.ruby-version')
        if full_jruby_version_string[0..5] == 'jruby-'
          @jruby_version = full_jruby_version_string[6..20].strip
          if @jruby_version =~ /\d+\.\d+\.\d+\.\d+/                        # check if the version is valid with four digits
            debug "Jarbler::Config.define_jruby_version: JRuby version used from .ruby-version file: #{@jruby_version}"
          else
            debug "Jarbler::Config.define_jruby_version: Invalid JRuby version in .ruby-version file (not four digits delimited by dot): #{full_jruby_version_string}"
            @jruby_version = nil
          end
        else
          debug "Jarbler::Config.define_jruby_version: Version info from .ruby-version file not applicable: #{full_jruby_version_string}"
        end
      end

      if @jruby_version.nil?                                                    # not yet defined in config file and .ruby-version file
        # no .ruby-version file to be used, use JRuby version of the latest Gem
        # Fetch the gem specification from Rubygems.org
        # search for the gem and get the JSON response
        response = Gem::SpecFetcher.fetcher.search_for_dependency(Gem::Dependency.new('jruby-jars'))
        debug("Jarbler::Config.define_jruby_version: Response from search_for_dependency = #{response.inspect}")
        # extract the versions from the response
        @jruby_version = response&.first&.first&.first&.version&.to_s
        raise "Unable to determine the latest available version of jruby-jars gem!\nResponse = #{response.inspect}" unless @jruby_version

        debug "Jarbler::Config.define_jruby_version: JRuby version from latest jruby-jars gem: #{jruby_version}"
      end
    end

    def debug(msg)
      puts msg if ENV['DEBUG']
    end

    # Avoid exception if using depprecated config attribute include_gems_to_compile
    def include_gems_to_compile=(_value)
      puts "Configuration attribute 'include_gems_to_compile' is deprecated. Use 'excludes_from_compile = [\"gems\"]' instead."
    end

    def validate_values
      raise "compile_java_version is not valid any more! Use config.java_opts instead with -source and -target." if compile_java_version
      raise "Invalid config value for jar name: #{jar_name}" unless jar_name =~ /\w+/
      raise "Invalid config value for executable: #{executable}" unless executable =~ /\w+/
      raise "Invalid config value for executable params: #{executable_params}" unless executable_params.is_a?(Array)
      raise "Invalid config value for includes: #{includes}" unless includes.is_a?(Array)
      raise "Invalid config value for excludes: #{excludes}" unless excludes.is_a?(Array)
      raise "Invalid config value for compile_ruby_files: #{compile_ruby_files}" unless [true, false].include?(compile_ruby_files)
      raise "compile_ruby_files = true is supported only with JRuby! Current runtime is '#{RUBY_ENGINE}'" if compile_ruby_files && (defined?(RUBY_ENGINE) && RUBY_ENGINE != 'jruby')
      raise "Invalid config value for excludes_from_compile: #{excludes_from_compile}" unless excludes_from_compile.is_a?(Array)
      raise "Invalid config value for jrubyc_opts, should by Array: #{jrubyc_opts}" unless jrubyc_opts.is_a?(Array)
      raise "Invalid config value for jruby_version: #{jruby_version}" unless jruby_version.nil? || jruby_version =~ /\d+\.\d+\.\d+\.\d+/
    end
  end
end