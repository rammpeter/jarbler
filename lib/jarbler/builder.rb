require 'rubygems'
require 'rubygems/dependency_installer'
require 'bundler'
require 'find'
require 'fileutils'
require 'yaml'
require 'open3'

module Jarbler
  class Builder
    # Execute all functions needed to build the jar file
    # Should be executed in application directory of Rails/Ruby application
    # @return [void]
    def build_jar
      debug "Running with Ruby version '#{RUBY_VERSION}' on platform '#{RUBY_PLATFORM}'. Engine '#{RUBY_ENGINE}' version '#{RUBY_ENGINE_VERSION}'"

      @config = nil # Ensure config is read from file or default. Necessary for testing only because of caching
      staging_dir = Dir.mktmpdir # create a temporary directory for staging
      app_root = Dir.pwd
      debug "Project dir: #{app_root}"

      ruby_minor_version = copy_jruby_jars_to_staging(staging_dir) # Copy the jruby jars to the staging directory
      exec_command "javac -nowarn -Xlint:deprecation -source 8 -target 8 -d #{staging_dir} #{__dir__}/JarMain.java" # Compile the Java files

      # Copy the application project to the staging directory
      FileUtils.mkdir_p("#{staging_dir}/app_root")
      config.includes.each do |dir|
        file_utils_copy("#{app_root}/#{dir}", "#{staging_dir}/app_root") if File.exist?("#{app_root}/#{dir}")
      end

      # Get the needed Gems
      raise "Gemfile.lock not found in #{app_root}" unless File.exist?("#{app_root}/Gemfile.lock")

      # Copy the needed Gems to the staging directory
      copy_needed_gems_to_staging(staging_dir, ruby_minor_version)

      Dir.chdir(staging_dir) do
        # create the manifest file
        File.open('Manifest.txt', 'w') do |file|
          file.write("Comment: created by Jarbler (https://github.com/rammpeter/jarbler)\n")
          file.write("Main-Class: JarMain\n")
        end

        # Write java properties file for use in JarMain.java
        File.open('jarbler.properties', 'w') do |file|
          file.write("jarbler.executable=#{config.executable}\n")
          # write a list of strings into property file delimited by space
          java_executable_params = ''
          config.executable_params.each do |param|
            java_executable_params += "#{param} "
          end
          file.write("jarbler.executable_params=#{java_executable_params.strip}\n")
          file.write("jarbler.compile_ruby_files=#{config.compile_ruby_files}\n")
          file.write("jarbler.gem_home_suffix=jruby/#{ruby_minor_version}\n")  # Extension after BUNDLE_PATH for local Gems
        end

        # remove files and directories from excludes, if they exist (after copying the rails project and the gems)
        config.excludes.each do |exclude|
          to_remove = "app_root/#{exclude}"
          if File.exist?(to_remove)
            debug "Removing #{to_remove} from staging directory"
            FileUtils.rm_rf(to_remove)
          else
            debug "Not removing #{to_remove} from staging directory, because it does not exist"
          end
        end

        compile_ruby_files if config.compile_ruby_files

        exec_command "jar cfm #{config.jar_name} Manifest.txt *" # create the jar file

        # place the jar in project directory
        file_utils_copy(config.jar_name, app_root)
        puts "Created jar file #{app_root}/#{config.jar_name}"
      end
    rescue Exception => e
      puts "Error: #{e.message}"
      puts e.backtrace.join("\n")
      raise
    ensure
      # remove temporary directory staging_dir
      if ENV['DEBUG']
        puts "Temporary directory #{staging_dir} not removed because of debug mode"
      else
        FileUtils.remove_entry staging_dir if staging_dir
      end
    end

    private

    # Copy the needed Gems to the staging directory
    # @param staging_dir [String] the staging directory
    # @param ruby_minor_version [String] the corresponding ruby minor version of the jruby jars version
    # @return [void]
    def copy_needed_gems_to_staging(staging_dir, ruby_minor_version)
      gem_target_location = "#{staging_dir}/gems/jruby/#{ruby_minor_version}"
      FileUtils.mkdir_p("#{gem_target_location}/bin")
      FileUtils.mkdir_p("#{gem_target_location}/build_info")
      FileUtils.mkdir_p("#{gem_target_location}/cache")
      FileUtils.mkdir_p("#{gem_target_location}/doc")
      FileUtils.mkdir_p("#{gem_target_location}/extensions")
      FileUtils.mkdir_p("#{gem_target_location}/gems")
      FileUtils.mkdir_p("#{gem_target_location}/specifications")
      FileUtils.mkdir_p("#{gem_target_location}/bundler/bin")
      FileUtils.mkdir_p("#{gem_target_location}/bundler/gems")

      needed_gems = gem_dependencies  # get the full names of the dependencies
      needed_gems.each do |needed_gem|
        # Get the location of the needed gem
        spec = Gem::Specification.find_by_name(needed_gem[:name], needed_gem[:version])
        raise "Gem #{needed_gem[:full_name]} not found for copying" unless spec
        debug "Found gem #{needed_gem[:full_name]} version #{needed_gem[:version]} in #{spec.gem_dir}"

        # differentiate between Gems from git/bundler and Gems from rubygems
        if spec.source.is_a?(Bundler::Source::Git)
          # Copy the Gem from bundler/gems including the gemspec
          file_utils_copy(spec.gem_dir, "#{gem_target_location}/bundler/gems")
          spec.executables.each do |executable|
            file_utils_copy("#{spec.bin_dir}/#{executable}", "#{gem_target_location}/bundler/bin")
          end
        else  # Gem is from rubygems
          # TODO: Gemfile could request a different version of default gem compared to the one jruby jars
          #       Therefore the default gems are also copied to the staging directory
          # unless spec.default_gem?  # Do not copy default gems, because they are already included in the jruby jars standard library
            # copy the Gem and gemspec separately
            file_utils_copy(spec.gem_dir, "#{gem_target_location}/gems")
            # spec.loaded_from contains the path to the gemspec file including the path prefix "default/" for default gems
            file_utils_copy(spec.loaded_from, "#{gem_target_location}/specifications")
            spec.executables.each do |executable|
              file_utils_copy("#{spec.bin_dir}/#{executable}", "#{gem_target_location}/bin")
            end
          # end
        end
      end
    rescue Exception => e
      debug("Builder.copy_needed_gems_to_staging: Failed with staging dir = '#{staging_dir}' and ruby minor version = #{ruby_minor_version} with #{e.class}\n#{e.message}")
      raise
    end

    # Read the default/production dependencies from Gemfile.lock and Gemfile
    # @return [Array] Array with Hashes containing: name, version, full_name
    def gem_dependencies
      needed_gems = []
      lockfile_parser = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile))
      lockfile_specs = lockfile_parser.specs

      Bundler.setup # Load Gems specified in Gemfile, ensure that Gem path also includes the Gems loaded into bundler dir
      # filter Gems needed for production
      gemfile_specs = Bundler.definition.dependencies.select do |d|
        d.groups.include?(:default) || d.groups.include?(:production)
      end

      debug "Gems from Gemfile needed for production:"
      gemfile_specs.each do |gemfile_spec|
        # find lockfile record for Gemfile spec
        lockfile_spec = lockfile_specs.find { |lockfile_spec| lockfile_spec.name == gemfile_spec.name }
        if lockfile_spec
          unless needed_gems.map{|n| n[:fullname]}.include?(lockfile_spec.full_name)
            needed_gems << { full_name: lockfile_spec.full_name, name: lockfile_spec.name, version: lockfile_spec.version }
          end
          debug "Direct Gem dependency: #{lockfile_spec.full_name}"
          add_indirect_dependencies(lockfile_specs, lockfile_spec, needed_gems)
        else
          if gemfile_spec.name == 'bundler'
            debug "Gem bundler found in Gemfile.lock, use version #{Bundler::VERSION}"
            needed_gems << { full_name: "bundler-#{lockfile_parser.bundler_version}", name: 'bundler', version: lockfile_parser.bundler_version }
          else
            debug "Gem #{gemfile_spec.name} not found in specs: in Gemfile.lock"
          end
        end
      end
      needed_gems.uniq.sort{|a,b| a[:full_name] <=> b[:full_name]}              # full_name also contains version
    rescue Exception => e
      debug("Builder.gem_dependencies: Failed with #{e.class}\n#{e.message}")
      raise
    end

    # recurively find all indirect dependencies
    # @param [Array] lockfile_specs Array of Bundler::LockfileParser::Spec objects
    # @param [Bundler::LockfileParser::Spec] lockfile_spec current lockfile spec to check for their dependencies
    # @param [Array] needed_gems Array with Hashes containing: name, version, full_name
    # @return [void]
    def add_indirect_dependencies(lockfile_specs, lockfile_spec, needed_gems)
      lockfile_spec.dependencies.each do |lockfile_spec_dep|
        lockfile_spec_found = lockfile_specs.find { |lockfile_spec| lockfile_spec.name == lockfile_spec_dep.name }
        if lockfile_spec_found
          debug "Indirect Gem dependency from #{lockfile_spec.full_name}: #{lockfile_spec_found.full_name}"
          unless needed_gems.map{|n| n[:fullname]}.include?(lockfile_spec_found.full_name)
            needed_gems << { full_name: lockfile_spec_found.full_name, name: lockfile_spec_found.name, version: lockfile_spec_found.version }
            add_indirect_dependencies(lockfile_specs, lockfile_spec_found, needed_gems)
          end
        else
          debug "Gem #{lockfile_spec_dep.name} not found in Gemfile.lock"
        end
      end
    rescue Exception => e
      debug("Builder.add_indirect_dependencies: Failed with #{e.class}\n#{e.message}")
      raise
    end

    # Output debug message if DEBUG environment variable is set
    # @param [String] msg Message to output
    # @return [void]
    def debug(msg)
      puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{msg}" if ENV['DEBUG']
    end

    # Get the config object
    # @return [Config] the config object
    def config
      if !defined?(@config) || @config.nil?
       @config = Config.create
       debug("Config attributes:")
       @config.instance_variables.each do |var|
         debug("#{var}: #{@config.instance_variable_get(var)}")
       end
       debug ""
      end
      @config
    rescue Exception => e
      debug("Builder.config: Failed with #{e.class}\n#{e.message}")
      raise
    end

    # Copy the jruby-jars to the staging directory
    # @param [String] staging_dir Path to the staging directory
    # @return [String] the minor ruby version of the JRuby jars with patch level set to 0
    def copy_jruby_jars_to_staging(staging_dir)

      debug "Copying JRuby Jars to staging dir: #{staging_dir}"
      # Ensure that jruby-jars gem is installed, otherwise install it. Accepts also bundler path in .bundle/config
      installed = nil                                                           # ensure that installed is defined outside of the block
      tries = 5
      tries.times do |try|
        begin
          installer = Gem::DependencyInstaller.new
          installed = installer.install('jruby-jars', config.jruby_version)
          break                                                               # escape loop if successful
        rescue Exception, RuntimeError => e
          debug "Builder.copy_jruby_jars_to_staging: Failed to install jruby-jars #{try}. try with #{e.class}\n#{e.message}"
          raise if try == tries - 1                                           # last try not successful
          sleeptime = 5
          debug "Builder.copy_jruby_jars_to_staging: Waiting #{sleeptime} seconds to prevent from Gem::RemoteFetcher::FetchError: IOError: closed stream"
          sleep sleeptime                                                     # wait x seconds before next try
        end
      end
      raise "jruby-jars gem not installed in version #{config.jruby_version}" if installed.empty?

      jruby_jars_location = installed[0]&.full_gem_path                         # need to be the first installed Gem
      debug "JRuby jars installed at: #{jruby_jars_location}"

      # Get the location of the jruby-jars gem
      # spec = Gem::Specification.find_by_name('jruby-jars', config.jruby_version)
      # jruby_jars_location = spec.gem_dir

      file_utils_copy("#{jruby_jars_location}/lib/jruby-core-#{config.jruby_version}-complete.jar", staging_dir)
      file_utils_copy("#{jruby_jars_location}/lib/jruby-stdlib-#{config.jruby_version}.jar", staging_dir)

      # Get the according Ruby version for the current JRuby version
      lines = exec_command "java -cp #{jruby_jars_location}/lib/jruby-core-#{config.jruby_version}-complete.jar org.jruby.Main --version"
      match_result = lines.match(/\(.*\)/)
      raise "Could not determine Ruby version for JRuby #{config.jruby_version} in following output:\n#{lines}" unless match_result
      ruby_version = match_result[0].tr('()', '')
      debug "Corresponding Ruby version for JRuby (#{config.jruby_version}): #{ruby_version}"
      ruby_minor_version = ruby_version.split('.')[0..1].join('.') + '.0'
      debug "Corresponding Ruby minor version for JRuby (#{config.jruby_version}): #{ruby_minor_version}"
      ruby_minor_version
    rescue Exception => e
      debug "Builder.copy_jruby_jars_to_staging: Failed to copy JRuby jars to staging dir '#{jruby_jars_location}' with #{e.class}\n#{e.message}"
      debug "Stack trace of exception:\n#{e.backtrace.join("\n")}"
      raise
    end

    # Execute the command in OS and return the output
    # @param [String] command Command to execute
    # @return [String] the output of the command
    def exec_command(command)
      debug("Execute by Open3.capture3: #{command}")
      stdout, stderr, status = Open3.capture3(command)
      debug "Command \"#{command}\" executed with return code #{status}!\nstdout:\n#{stdout}\n\nstderr:\n#{stderr}\n"
      raise "Command \"#{command}\" failed with return code #{status}!\nstdout:\n#{stdout}\n\nstderr:\n#{stderr}\n" unless status.success?
      "stdout:\n#{stdout}\nstderr:\n#{stderr}\n"
    rescue Exception => e
      debug "Builder.exec_command: Failed to execute command '#{command}' with #{e.class}\n#{e.message}"
      raise
    end

    # Copy file or directory with error handling
    # @param [String] source Path to the source file or directory
    # @param [String] destination Path to the destination file or directory
    # @return [void]
    def file_utils_copy(source, destination)
      if File.exist?(source) && File.directory?(source)
        FileUtils.cp_r(source, destination)
      else
        FileUtils.cp(source, destination)
      end
    rescue Exception => e
      debug "Builder.file_utils_copy: Failed to copy '#{source}' to '#{destination}' with #{e.class}\n#{e.message}"
      raise
    end

    # Compile all Ruby files in the current directory (staging directory)
    def compile_ruby_files
      require 'jruby/jrubyc'

      puts "Compiling all .rb files to .class files"
      # Inform if used JRuby version is different from the intended runtime JRuby version
      if JRUBY_VERSION != config.jruby_version
        puts "Compiling .rb files to .class is done with JRuby version #{JRUBY_VERSION}, but intended runtime JRuby version for jar file  is #{config.jruby_version}"
      end

      # Compile all .rb files in the current directory tree, but not in the gems directory
      ruby_files = Find.find('.').select { |f| f =~ /\.rb$/ && !f.include?("#{File::SEPARATOR}gems#{File::SEPARATOR}") }                   # find all Ruby files in the current directory

      # Exclude named files or directories from compiling
      config.excludes_from_compile.each do |exclude|
        ruby_files = ruby_files.select { |f| !(f =~ /\.#{File::SEPARATOR}#{exclude}/) }
      end

      ruby_files.each do |ruby_file|
        debug "Compile Ruby file #{ruby_file}"
        full_file_name = File.join(Dir.pwd, ruby_file)                          # full name including path is required by the JRuby compiler
        begin
          status = JRuby::Compiler::compile_argv([full_file_name])              # compile the Ruby file
          if status == 0
            File.delete(full_file_name)                                         # remove the original Ruby file to ensure that the compiled class file is used
          else
            raise "Return status != 0"
          end
        rescue Exception => e
          puts "Error compiling Ruby file '#{ruby_file}': #{e.class}:#{e.message}"
          puts "'#{ruby_file}' is not compiled and will be included in the jar file as original Ruby file"
        end
      end
    rescue Exception => e
      puts "Builder.compile_ruby_files: Failed to compile Ruby files with #{e.class}\n#{e.message}"
      raise
    end
  end
end