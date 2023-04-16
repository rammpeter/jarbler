module Jarbler
  class Builder
    def build_jar
      # create a temporary directory for staging
      staging_dir = Dir.mktmpdir

      jarbler_lib_dir = __dir__
      rails_root = Dir.pwd
      puts "Project dir: #{rails_root}"

      # read the file RAILS_ROOT/.ruby-version starting from char at position 6 to the end of the line
      requested_ruby_version = File.read("#{rails_root}/.ruby-version")[6..20].strip
      puts "JRUBY_VERSION=#{JRUBY_VERSION}"
      if requested_ruby_version != JRUBY_VERSION
        puts "ERROR: requested jRuby version #{requested_ruby_version} from .ruby-version does not match current jRuby version #{JRUBY_VERSION}"
        exit 1
      end

      # requires that default Gem location is used (no BUNDLE_PATH: "vendor/bundle" in .bundle/config)
      # TODO: allow BUNDLE_PATH: "vendor/bundle" in .bundle/config)
      jruby_jars_location = nil
      `bundle info jruby-jars`.lines.each do |line|
        if line.match(JRUBY_VERSION) && line.match(/Path:/)
          jruby_jars_location = line.split[1]
          puts "Location of jRuby jars: #{jruby_jars_location}"
        end
      end

      # Compile the Java files
      puts `javac -d #{staging_dir} #{jarbler_lib_dir}/JarMain.java`
      raise "Java compilation failed" unless $?.success?

      FileUtils.cp("#{jruby_jars_location}/lib/jruby-core-#{JRUBY_VERSION}-complete.jar", staging_dir)
      FileUtils.cp("#{jruby_jars_location}/lib/jruby-stdlib-#{JRUBY_VERSION}.jar", staging_dir)


      # Copy the Rails project to the staging directory
      FileUtils.mkdir_p("#{staging_dir}/rails_app")
      config.includes.each do |dir|
        FileUtils.cp_r("#{rails_root}/#{dir}", "#{staging_dir}/rails_app") if File.exist?("#{rails_root}/#{dir}")
      end

      # Get the needed Gems
      raise "Gemfile.lock not found in #{rails_root}" unless File.exist?("#{rails_root}/Gemfile.lock")

      FileUtils.mkdir_p("#{staging_dir}/gems")
      FileUtils.mkdir_p("#{staging_dir}/gems/specifications")
      FileUtils.mkdir_p("#{staging_dir}/gems/gems")

      # Search locations of gems in Gemfile.lock
      gem_search_locations = []
      bundle_config_bundle_path = nil
      # Add possible local config first in search list
      gem_search_locations << bundle_config_bundle_path(rails_root) if bundle_config_bundle_path(rails_root)
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
          FileUtils.rm_rf(exclude)
        end

        # create the jar file
        puts `jar cfm #{config.jar_name} Manifest.txt *`
        raise "jar call failed" unless $?.success?

        # place the jar in project directory
        FileUtils.cp(config.jar_name, rails_root)

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
  end
end