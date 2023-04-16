# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'bundler'
require 'bundler/lockfile_parser'

require_relative "jarbler/version"
require_relative "jarbler/builder"
require_relative "jarbler/config"


module Jarbler
  def self.run
    puts "Jarbler release #{VERSION}"
    Builder.new.build_jar
  end

  def self.config
    Jarbler::Config.new.create_config_file
  end
end
