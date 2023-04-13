# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
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
    FileUtils.cp_r("#{rails_root}", staging_dir)

    # Use fixed name for Rails project directory
    FileUtils.mv("#{staging_dir}/#{File.basename(rails_root)}", "#{staging_dir}/rails_app")

    # Get the needed Gems
    raise "Gemfile.lock not found in #{rails_root}" unless File.exist?("#{rails_root}/Gemfile.lock")

    # Read all lines of Gemfile.lock into an array
    gemfile_lock = File.readlines("#{rails_root}/Gemfile.lock")
    active_line = false
    gemfile_lock.each do |line|
      active_line = true if line.match(/specs/)
      active_line = false if line.match(/PLATFORMS/)
      if active_line && !line.match(/specs/) && line[4] != ' '
        gem_name = line.split[0]
        gem_version = line.split[1]
        unless gem_version.nil?                             # ignore gems without version
          Jarbler.copy_gem_to_staging(gem_name, gem_version.gsub(/\(|\)/, ''), staging_dir)
        end
      end
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
  def self.copy_gem_to_staging(gem_name, gem_version, staging_dir)
    puts "#{gem_name} #{gem_version}"
  end

end
