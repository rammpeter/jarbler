# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in jarbler.gemspec
gemspec

# gem "rake", "~> 13.0"
gem "rake"

# suspend rdoc due to error "NameError: cannot load (ext) (org.jruby.ext.psych.PsychLibrary)"o
# group(:development) do
#   gem 'rdoc'
# end

group(:test)  do
  gem 'minitest'
  gem 'minitest-reporters'
end