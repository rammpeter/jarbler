require 'bundler'

module Jarbler
  class Builder
    # Execute all functions needed to build the jar file
    # Should be executed in application directory of Rails/Ruby application
    # @return [void]
    def build_jar
      # create a temporary directory for staging
      staging_dir = Dir.mktmpdir

      jarbler_lib_dir = __dir__
      app_root = Dir.pwd
      debug "Project dir: #{app_root}"

      exec_command  "gem install --no-doc jruby-jars -v #{config.jruby_version}" # Ensure that jruby-jars are installed in the requested version
      copy_jruby_jars_sto_staging(staging_dir) # Copy the jruby jars to the staging directory
      exec_command "javac -d #{staging_dir} #{jarbler_lib_dir}/JarMain.java" # Compile the Java files

      # Copy the application project to the staging directory
      FileUtils.mkdir_p("#{staging_dir}/app_root")
      config.includes.each do |dir|
        FileUtils.cp_r("#{app_root}/#{dir}", "#{staging_dir}/app_root") if File.exist?("#{app_root}/#{dir}")
      end

      # Get the needed Gems
      raise "Gemfile.lock not found in #{app_root}" unless File.exist?("#{app_root}/Gemfile.lock")

      FileUtils.mkdir_p("#{staging_dir}/gems")
      FileUtils.mkdir_p("#{staging_dir}/gems/specifications")
      FileUtils.mkdir_p("#{staging_dir}/gems/gems")

      # Search locations of gems in Gemfile.lock
      gem_search_locations = []
      # Add possible local config first in search list
      gem_search_locations << bundle_config_bundle_path(app_root) if bundle_config_bundle_path(app_root)
      ENV['GEM_PATH'].split(':').each do |gem_path|
        gem_search_locations << gem_path
      end

      needed_gems = gem_dependencies
      needed_gems.each do |gem|
        copy_gem_to_staging(gem[:name], gem[:version], staging_dir, gem_search_locations)
      end

      Dir.chdir(staging_dir) do
        # create the manifest file
        File.open('Manifest.txt', 'w') do |file|
          file.write("Comment: created by Jarbler (https://github.com/rammpeter/jarbler)\n")
          file.write("Main-Class: JarMain\n")
        end

        # Write java properties file for use in JarMain.java
        File.open('jarbler.properties', 'w') do |file|
          file.write("jarbler.port=#{config.port}\n")
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
        FileUtils.cp(config.jar_name, app_root)

      end

      # remove temporary directory staging_dir
      FileUtils.remove_entry staging_dir

    end

    private
    def copy_gem_to_staging(gem_name, gem_version, staging_dir, gem_search_locations)
      gem_search_locations.each do |gem_search_location|
        gem_dir = "#{gem_search_location}/gems/#{gem_name}-#{gem_version}"
        if File.exist?(gem_dir)
          FileUtils.cp_r(gem_dir, "#{staging_dir}/gems/gems")
          FileUtils.cp("#{gem_search_location}/specifications/#{gem_name}-#{gem_version}.gemspec", "#{staging_dir}/gems/specifications")
          return
        end
      end
    end

    # Read the dependencies from Gemfile.lock and Gemfile
    # @return [Array] Array of dependencies
    def gem_dependencies
      needed_gems = []
      lockfile_specs = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile)).specs

      Bundler.setup # Load Gems specified in Gemfile
      # filter Gems needed for production
      gemfile_specs = Bundler.definition.dependencies.select do |d|
        d.groups.include?(:default) || d.groups.include?(:production)
      end

      debug "Gems from Gemfile needed for production:"
      gemfile_specs.each do |gemfile_spec|
        # find lockfile record for Gemfile spec
        lockfile_spec = lockfile_specs.find { |lockfile_spec| lockfile_spec.name == gemfile_spec.name }
        if lockfile_spec
          needed_gem = { name: gemfile_spec.name, version: lockfile_spec.version.version }
          needed_gems << needed_gem
          debug "Direct Gem: #{needed_gem[:name]} #{needed_gem[:version]}"
          lockfile_spec.dependencies.each do |lockfile_spec_dep|
            lockfile_spec = lockfile_specs.find { |lockfile_spec| lockfile_spec.name == lockfile_spec_dep.name }
            if lockfile_spec
              needed_gem =  { name: lockfile_spec_dep.name, version: lockfile_spec.version.version }
              needed_gems << needed_gem
              debug "Indirect Gem: #{needed_gem[:name]} #{needed_gem[:version]}"
            else
              debug "Gem #{lockfile_spec_dep.name} not found in Gemfile.lock"
            end
          end

        else
          debug "Gem #{gemfile_spec.name} not found in Gemfile.lock"
        end
      end
      needed_gems.uniq.sort{ |a,b| a[:name] <=> b[:name]}
    end

    def debug(msg)
      puts msg if ENV['DEBUG']
    end

    def config
      unless defined? @config
       @config = Config.create
       debug("Config attributes:")
       @config.instance_variables.each do |var|
         debug("#{var}: #{@config.instance_variable_get(var)}")
       end
       debug ""
      end
      @config
    end

    def bundle_config_bundle_path(rails_root)
      bundle_path = nil # default
      if File.exist?("#{rails_root}/.bundle/config")
        bundle_config = YAML.load_file("#{rails_root}/.bundle/config")
        if bundle_config && bundle_config['BUNDLE_PATH']
          bundle_path "#{rails_root}/#{bundle_config['BUNDLE_PATH']}"
        end
      end
      bundle_path
    end

    def copy_jruby_jars_sto_staging(staging_dir)
      lines = exec_command "gem info jruby-jars -v #{config.jruby_version}"
      jruby_jars_location = nil
      lines.split("\n").each do |line|
        if line.match(config.jruby_version) && line.match(/Installed at/)
          jruby_jars_location = "#{line.split(':')[1].strip}/gems/jruby-jars-#{config.jruby_version}"
          debug "Location of jRuby jars: #{jruby_jars_location}"
          break
        end
      end
      raise "Could not determine location of jRuby jars in following output:\n#{lines}" unless jruby_jars_location
      FileUtils.cp("#{jruby_jars_location}/lib/jruby-core-#{config.jruby_version}-complete.jar", staging_dir)
      FileUtils.cp("#{jruby_jars_location}/lib/jruby-stdlib-#{config.jruby_version}.jar", staging_dir)
    end

    # Execute the command and return the output
    def exec_command(command)
      lines = `#{command}`
      raise "Command \"#{command}\"failed with return code #{$?} and output:\n#{lines}" unless $?.success?
      debug "Command \"#{command}\" executed successfully with following output:\n#{lines}"
      lines
    end
  end
end