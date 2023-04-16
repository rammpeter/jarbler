# Jarbler
Pack a Ruby on Rails application into an executable jar file.

Jarbler allows you to create an self executing Java jar file containing your Ruby on Rails application.
The application is executed using jRuby.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add jarbler --group "development"

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install jarblerö

## Usage

To create a jar file simply run "jarble" in your application's root directory.

    $ jarble
    
To adjust Jarbler's configuration, modify the settings in config file ´config/jarble.rb´. The template for this config file you create by executing

    $ jarble config

### Preconditions
* The Rails app should be capable of running with jRuby
* Gems with native extensions should not be used (e.g. sassc)
  * if needed for development or test such Gems with native extensions should be moved to the development and test group in the Gemfile.
  * Otherwise the created jar file may not be executable on all platforms and Java versions.

## Run the created jar file
The jar file created by Jarbler can be executed by

    $ java -jar <jar file name>
    
Additional command line parameters are passed through to the executed Ruby app (like "-p 8900" for different network port number with bin/rails)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rammpeter/jarbler.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
