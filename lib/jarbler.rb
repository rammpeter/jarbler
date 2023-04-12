# frozen_string_literal: true

require 'fileutils'
require_relative "jarbler/version"

module Jarbler
  class Error < StandardError; end
  # Your code goes here...

  def self.run
    puts "Jarbler release #{VERSION}"


    rails_root = __dir__

    # read the file RAILS_ROOT/.ruby-version starting from char at position 6 to the end of the line
    requested_ruby_version = File.read("#{rails_root}/.ruby-version")[6..20].strip
    puts "JRUBY_VERSION=#{JRUBY_VERSION}"
    if requested_ruby_version != JRUBY_VERSION
      puts "ERROR: requested jRuby version #{requested_ruby_version} from .ruby-version does not match current jRuby version #{JRUBY_VERSION}"
      exit 1
    end

    # requires that default Gem location is used (no BUNDLE_PATH: "vendor/bundle" in .bundle/config)
    `bundle info jruby-jars`.lines.each do |line|
      if line.match(JRUBY_VERSION) && line.match(/Path:/)
        JRUBY_JARS_LOCATION = line.split[1]
        puts "JRUBY_JARS_LOCATION=#{JRUBY_JARS_LOCATION}"
      end
    end

    # Compile the Java files
    puts `javac JarMain.java`

    # Remove all jar files
    Dir.glob('*.jar').each { |file| File.delete(file)}
    FileUtils.cp("#{JRUBY_JARS_LOCATION}/lib/jruby-core-#{JRUBY_VERSION}-complete.jar", '.')
    FileUtils.cp("#{JRUBY_JARS_LOCATION}/lib/jruby-stdlib-#{JRUBY_VERSION}.jar", '.')

    puts `jar cvfm Panorama.jar Manifest.txt JarMain.class *.jar`

    # Show content of created jar file
    puts "\nContent of created jar file:"
    puts `jar tvf Panorama.jar`



  end

  private

end
