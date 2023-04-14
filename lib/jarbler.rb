# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'bundler'
require 'bundler/lockfile_parser'

require_relative "jarbler/version"

module Jarbler
  class Error < StandardError; end
  # Your code goes here...

  def self.run
    puts "Jarbler release #{VERSION}"

    # create a temporary directory for staging
    staging_dir = Dir.mktmpdir

    jarbler_lib_dir = __dir__
    rails_root = Dir.pwd
    puts "Project dir: #{rails_root}"
    jar_name = File.basename(rails_root) + '.jar'

    # read the file RAILS_ROOT/.ruby-version starting from char at position 6 to the end of the line
    requested_ruby_version = File.read("#{rails_root}/.ruby-version")[6..20].strip
    puts "JRUBY_VERSION=#{JRUBY_VERSION}"
    if requested_ruby_version != JRUBY_VERSION
      puts "ERROR: requested jRuby version #{requested_ruby_version} from .ruby-version does not match current jRuby version #{JRUBY_VERSION}"
      exit 1
    end

    # requires that default Gem location is used (no BUNDLE_PATH: "vendor/bundle" in .bundle/config)
    jruby_jars_location = nil
    `bundle info jruby-jars`.lines.each do |line|
      if line.match(JRUBY_VERSION) && line.match(/Path:/)
        jruby_jars_location = line.split[1]
        puts "Location of jRuby jars: #{jruby_jars_location}"
      end
    end

    # Compile the Java files
    puts `javac -d #{staging_dir} #{jarbler_lib_dir}/JarMain.java`

    FileUtils.cp("#{jruby_jars_location}/lib/jruby-core-#{JRUBY_VERSION}-complete.jar", staging_dir)
    FileUtils.cp("#{jruby_jars_location}/lib/jruby-stdlib-#{JRUBY_VERSION}.jar", staging_dir)


    # Copy the Rails project to the staging directory
    FileUtils.mkdir_p("#{staging_dir}/rails_app")
    app_dirs = %w(app bin config db Gemfile Gemfile.lock lib log script vendor tmp)
    app_dirs.each do |dir|
      FileUtils.cp_r("#{rails_root}/#{dir}", "#{staging_dir}/rails_app") if File.exist?("#{rails_root}/#{dir}")
    end

    # Get the needed Gems
    raise "Gemfile.lock not found in #{rails_root}" unless File.exist?("#{rails_root}/Gemfile.lock")

    FileUtils.mkdir_p("#{staging_dir}/gems")
    FileUtils.mkdir_p("#{staging_dir}/gems/specifications")
    FileUtils.mkdir_p("#{staging_dir}/gems/gems")

    # Search locations of gems in Gemfile.lock
    gem_search_locations = []
    ENV['GEM_PATH'].split(':').each do |gem_path|
      gem_search_locations << gem_path
    end
    if File.exist?("#{rails_root}/.bundle/config")
      bundle_config = YAML.load_file("#{rails_root}/.bundle/config")
      if bundle_config && bundle_config['BUNDLE_PATH']
        gem_search_locations << "#{rails_root}/#{bundle_config['BUNDLE_PATH']}"
      end
    end

    needed_gems = self.gem_dependencies
    needed_gems.each do |gem|
      self.copy_gem_to_staging(gem[:name], gem[:version], staging_dir, gem_search_locations)
    end

    Dir.chdir(staging_dir) do
      # create the manifest file
      File.open('Manifest.txt', 'w') { |file| file.write("Main-Class: JarMain\n") }

      puts `jar cfm #{jar_name} Manifest.txt *`

      # Show content of created jar file
      #puts "\nContent of created jar file:"
      #puts `jar tvf #{jar_name}`

      # place the jar in project directory
      FileUtils.cp(jar_name, rails_root)

    end

    # remove temporary directory staging_dir
    FileUtils.remove_entry staging_dir

  end

  private
  def self.copy_gem_to_staging(gem_name, gem_version, staging_dir, gem_search_locations)
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
  def self.gem_dependencies
    needed_gems = []
    lockfile_specs = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile)).specs

    Bundler.setup # Load Gems specified in Gemfile
    # filter Gems needed for production
    gemfile_specs = Bundler.definition.dependencies.select do |d|
      d.groups.include?(:default) || d.groups.include?(:production)
    end

    self.debug "Gems from Gemfile needed for production:"
    gemfile_specs.each do |gemfile_spec|
      # find lockfile record for Gemfile spec
      lockfile_spec = lockfile_specs.find { |lockfile_spec| lockfile_spec.name == gemfile_spec.name }
      if lockfile_spec
        needed_gem = { name: gemfile_spec.name, version: lockfile_spec.version.version }
        needed_gems << needed_gem
        self.debug "Direct Gem: #{needed_gem[:name]} #{needed_gem[:version]}"
        lockfile_spec.dependencies.each do |lockfile_spec_dep|
          lockfile_spec = lockfile_specs.find { |lockfile_spec| lockfile_spec.name == lockfile_spec_dep.name }
          if lockfile_spec
            needed_gem =  { name: lockfile_spec_dep.name, version: lockfile_spec.version.version }
            needed_gems << needed_gem
            self.debug "Indirect Gem: #{needed_gem[:name]} #{needed_gem[:version]}"
          else
            self.debug "Gem #{lockfile_spec_dep.name} not found in Gemfile.lock"
          end
        end

      else
        self.debug "Gem #{gemfile_spec.name} not found in Gemfile.lock"
      end
    end
    needed_gems.uniq.sort{ |a,b| a[:name] <=> b[:name]}
  end

  def self.debug(msg)
    puts msg if ENV['DEBUG']
  end


end
