require 'rubygems'
require 'rubygems/dependency_installer'
require 'bundler'
require 'find'
require 'fileutils'
require 'yaml'

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

      ruby_version = copy_jruby_jars_to_staging(staging_dir) # Copy the jruby jars to the staging directory
      exec_command "javac -nowarn -Xlint:deprecation -source 8 -target 8 -d #{staging_dir} #{__dir__}/JarMain.java" # Compile the Java files

      # Copy the application project to the staging directory
      FileUtils.mkdir_p("#{staging_dir}/app_root")
      config.includes.each do |dir|
        file_utils_copy("#{app_root}/#{dir}", "#{staging_dir}/app_root") if File.exist?("#{app_root}/#{dir}")
      end

      # Get the needed Gems
      raise "Gemfile.lock not found in #{app_root}" unless File.exist?("#{app_root}/Gemfile.lock")

      gem_target_location = "#{staging_dir}/gems/jruby/#{ruby_version}"
      FileUtils.mkdir_p("#{gem_target_location}/gems")
      FileUtils.mkdir_p("#{gem_target_location}/specifications")

      # Copy the needed Gems to the staging directory
      copy_needed_gems_to_staging(gem_target_location, app_root)

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

        exec_command "jar cfm #{config.jar_name} Manifest.txt *" # create the jar file

        # place the jar in project directory
        file_utils_copy(config.jar_name, app_root)
        puts "Created jar file #{app_root}/#{config.jar_name}"
      end

      # remove temporary directory staging_dir
      FileUtils.remove_entry staging_dir

    end

    private


    # Check if there is an additional local bundle path in .bundle/config
    def bundle_config_bundle_path(rails_root)
      bundle_path = nil # default
      if File.exist?("#{rails_root}/.bundle/config")
        bundle_config = YAML.load_file("#{rails_root}/.bundle/config")
        if bundle_config && bundle_config['BUNDLE_PATH']
          bundle_path = "#{rails_root}/#{bundle_config['BUNDLE_PATH']}"
          debug "Local Gem path configured in #{rails_root}/.bundle/config: #{bundle_path}"
        end
      end
      bundle_path
    end

    # Copy the needed Gems to the staging directory
    # @param [String] gem_target_location Path to the staging directory
    # @return [void]
    def copy_needed_gems_to_staging(gem_target_location, app_root)
      #Bundler.with_unbundled_env do # No previous setting inherited like Gemfile location
      #  Bundler.reset! # Reset settings from previous Bundler.with_unbundled_env
        needed_gems = gem_dependencies  # get the full names of the dependencies
        needed_gems.each do |needed_gem|
          # Get the location of the needed gem
          spec = Gem::Specification.find_by_name(needed_gem[:name], needed_gem[:version])
          raise "Gem #{needed_gem[:full_name]} not found for copying" unless spec
          debug "Found gem #{needed_gem[:full_name]} version #{needed_gem[:version]} in #{spec.gem_dir}"
          file_utils_copy(spec.gem_dir, "#{gem_target_location}/gems")
          file_utils_copy("#{spec.gem_dir}/../../specifications/#{needed_gem[:full_name]}.gemspec", "#{gem_target_location}/specifications")
          # end
      end
    end

    # Read the default/production dependencies from Gemfile.lock and Gemfile
    # @return [Array] Array with full names of dependencies
    def gem_dependencies
      needed_gems = []
      lockfile_specs = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile)).specs

      # Bundler.setup # Load Gems specified in Gemfile
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
          debug "Gem #{gemfile_spec.name} not found in Gemfile.lock"
        end
      end
      needed_gems.uniq.sort{|a,b| a[:full_name] <=> b[:full_name]}
    end

    # recurively find all indirect dependencies
    # @param [Array] lockfile_specs Array of Bundler::LockfileParser::Spec objects
    # @param [Bundler::LockfileParser::Spec] lockfile_spec current lockfile spec to check for their dependencies
    # @param [Array] needed_gems Array with full names of already found dependencies, add findings here
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
    end
    def debug(msg)
      puts msg if ENV['DEBUG']
    end

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
    end

    # Copy the jruby-jars to the staging directory
    # @param [String] staging_dir Path to the staging directory
    # @param [Array] gem_search_locations Array of Gem locations to look for jRuby jars
    # @return [String] the ruby version of the jRuby jars
    def copy_jruby_jars_to_staging(staging_dir)

      # Ensure that jruby-jars gem is installed, otherwise install it. Accepts also bundler path in .bundle/config
      installer = Gem::DependencyInstaller.new
      installed = installer.install('jruby-jars', config.jruby_version)
      raise "jruby-jars gem not installed in version #{config.jruby_version}" if installed.empty?

      jruby_jars_location = installed[0]&.full_gem_path
      debug "jRuby jars installed at: #{jruby_jars_location}"

      # Get the location of the jruby-jars gem
      # spec = Gem::Specification.find_by_name('jruby-jars', config.jruby_version)
      # jruby_jars_location = spec.gem_dir

      file_utils_copy("#{jruby_jars_location}/lib/jruby-core-#{config.jruby_version}-complete.jar", staging_dir)
      file_utils_copy("#{jruby_jars_location}/lib/jruby-stdlib-#{config.jruby_version}.jar", staging_dir)

      # Get the according Ruby version for the current jRuby version
      lines = exec_command "java -cp #{jruby_jars_location}/lib/jruby-core-#{config.jruby_version}-complete.jar org.jruby.Main --version"
      match_result = lines.match(/\(.*\)/)
      raise "Could not determine Ruby version for jRuby #{config.jruby_version} in following output:\n#{lines}" unless match_result
      ruby_version = match_result[0].tr('()', '')
      debug "Corresponding Ruby version for jRuby (#{config.jruby_version}): #{ruby_version}"
      ruby_version
    end

    # Execute the command and return the output
    def exec_command(command)
      lines = `#{command}`
      raise "Command \"#{command}\"failed with return code #{$?} and output:\n#{lines}" unless $?.success?
      debug "Command \"#{command}\" executed successfully with following output:\n#{lines}"
      lines
    end

    # Copy file or directory with error handling
    def file_utils_copy(source, destination)
      if File.exist?(source) && File.directory?(source)
        FileUtils.cp_r(source, destination)
      else
        FileUtils.cp(source, destination)
      end
    rescue Exception
      puts "Error copying #{source} to #{destination}"
      raise
    end
  end

end