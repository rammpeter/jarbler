# frozen_string_literal: true

require_relative "lib/jarbler/version"

Gem::Specification.new do |spec|
  spec.name = "jarbler"
  spec.version = Jarbler::VERSION
  spec.authors = ["Peter Ramm"]
  spec.email = ["Peter@ramm-oberhermsdorf.de"]

  spec.summary = "Pack a Ruby app into a Java jar file"
  spec.description = "Pack a Ruby app combined with JRuby runtime and all its Gem dependencies into a jar file to simply run the app on any Java platform by '> java -jar file.jar'"
  spec.homepage = "https://github.com/rammpeter/jarbler"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rammpeter/jarbler"
  spec.metadata["changelog_uri"] = "https://github.com/rammpeter/jarbler/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "bin"
  spec.executables << 'jarble'
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
