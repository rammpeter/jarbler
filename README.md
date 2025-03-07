![# Jarbler](doc/images/jarbler_logo.png)

Pack a Ruby application into an executable jar file.

Jarbler creates a self executing Java jar file containing a Ruby application and all its Gem dependencies.

This tool is inspired by the widely used JRuby runner Warbler. 
The configured Ruby program is directly executed inside the JVM using the JRuby runtime jars.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add jarbler --group "development"

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install jarbler
    
[![Gem Version](https://badge.fury.io/rb/jarbler.svg)](https://badge.fury.io/rb/jarbler)

## Usage

To create a jar file simply run "jarble" in your application's root directory.

    $ jarble
    
To adjust Jarbler's configuration, modify the settings in config file ´config/jarble.rb´. The template for this config file you create by executing

    $ jarble config

### Preconditions
* Dependency handling should be based on Bundler (existence of Gemfile is required)
* The Ruby app should be capable of running with JRuby
* Gems with native extensions should not be used (e.g. sassc)
  * if needed for development or test such Gems with native extensions should be moved to the development and test group in the Gemfile.
  * Otherwise the created jar file may not be executable on all platforms and Java versions.

## Run the created jar file
The jar file created by Jarbler can be executed by

    $ java -jar <jar filename>
    
Additional command line parameters are passed through to the executed Ruby app (like "-p 8900" for different network port number with bin/rails)

## Configuration

The file config/jarble.rb contains the configuration for Jarbler. 
To create a template config file with information about all the supported configuration options, execute:

    $ jarble config

The default configuration is focused on Ruby on Rails applications.<br>

### Configuration options
| Option                  | Default value                                                                                              | Description                                                                                                                                                                                    |
|-------------------------|------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| compile_ruby_files      | false                                                                                                      | Ahead of time compilation of all .rb files of the application to .class files. Onl the .class files are stored in the jar file. The Gem dependencies are not compiled. Requires JRuby runtime. |
| executable              | "bin/rails"                                                                                                | The ruby start file to run at execution of jar file. File extension .class is used automatically if start file is .rb and AOT compilation is used.                                             |
| executable_params       | ["server", "-e", "production", "-p", "8080"]                                                               | Command line parameters to be used for the ruby executable                                                                                                                                     |
| excludes_from_compile   | []                                                                                                         | The files and dirs of the project to exclude from the compilation of .rb files. Paths specifies the location in the jar file (e.g. ["app_root/file.rb"] )                                      |
| excludes                | ["tmp/cache", "tmp/pids", ...] (see generated template file for whole content)                             | The files and dirs of the project to exclude from the include option                                                                                                                           |
| includes                | ["app", "bin", "config", ...] (see generated template file for whole content)                              | The files and dirs of the project to include in the jar file                                                                                                                                   |
| jar_name                | &lt; Name of project dir &gt;.jar                                                                          | The name of the generated jar file                                                                                                                                                             |
| jruby_version           | A valid JRuby version from file '.ruby-version' or the current most recent version of the Gem 'jruby-jars' | The version of the JRuby runtime to use                                                                                                                                                        |


## Troubleshooting
* Set DEBUG=true in OS environment to get additional runtime information
* The temporary folder with the extracted app and JRuby runtime files is not deleted after execution if DEBUG is set.

### Possible error messages
* Gem::LoadError: You have already activated ..., but your Gemfile requires ... . Since ... is a default gem, you can either remove your dependency on it or try updating to a newer version of bundler that supports net-protocol as a default gem.
  * Reason: Mismatch between the version of the local requested gem and the version of the default gem
  * Solution: Update the default gems to the requested version


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rammpeter/jarbler. <br>
Any feedback about usage experience or missing features is also appreciated.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
