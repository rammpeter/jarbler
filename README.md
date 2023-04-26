# Jarbler
Pack a Ruby application into an executable jar file.

Jarbler allows you to create an self executing Java jar file containing your Ruby application and all its Gem dependencies.

This tool is inspired by the widely used jRuby runner Warbler. 
In contrast to Warbler no Java servlet container is needed for execution.
Instead the configured Ruby program is directly executed inside the JVM using the jRuby runtime jars.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add jarbler --group "development"

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install jarbler

## Usage

To create a jar file simply run "jarble" in your application's root directory.

    $ jarble
    
To adjust Jarbler's configuration, modify the settings in config file ´config/jarble.rb´. The template for this config file you create by executing

    $ jarble config

### Preconditions
* The Ruby app should be capable of running with jRuby
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

The default configuration supports Ruby on Rails applications.<br>
The executable is set to "bin/rails" by default.<br>
The default executable parameters are  "server -p 8080 -e production".

## Troubleshooting
* Set DEBUG=true in environment to get additional runtime information
* The temporary folder with the extracted app and jRuby runtime files is not deleted after execution if DEBUG is set.

### Possible error messages
* Gem::LoadError: You have already activated ..., but your Gemfile requires ... . Since ... is a default gem, you can either remove your dependency on it or try updating to a newer version of bundler that supports net-protocol as a default gem.
  * Reason: Mismatch between the version of the local requested gem and the version of the default gem
  * Solution: Update the default gems to the requested version


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rammpeter/jarbler. <br>
Any feedback about usage experience or missing features is also appreciated.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
