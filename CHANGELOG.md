## [Unreleased]

## [0.3.3] - 2025-03-04

- Set environment GEM_HOME to the final gem location after extraction of the jar file by setting the system property `jruby.gem.home=...`<br/>
This ensures that Gems are found also for native Ruby code without using Bundler.<br/>
- Accept jar file locations with blanks in the path, especially for Windows
- Setting `compile_ruby_files=true` compiles only .rb file of the application, but does not compile the .rb files in Gems.<br/>
  Compiling the Gems also remains an open task.
- Bugfix: Accept spaces in the path to the jar file, especially for Windows

## [0.3.1] - 2024-07-02

- Use file .ruby-version to define the JRuby version for the jar file only if .ruby-version contains a valid jRuby version


## [0.3.0] - 2024-06-18

- excludes_from_compile specifies paths as the location in the jar file
- Desupport of configuration attribute include_gems_to_compile

## [0.2.3] - 2024-06-13

- Show used configuration values in log output

## [0.2.2] - 2024-06-13

- Exclude certain dirs or files from compilation with 'excludes_from_compile' option in config file

## [0.2.1] - 2024-06-13

- Ruby files remain originally in jar if compile fails for a single file. 
- Gems are compiled only if include_gems_to_compile=true

## [0.2.0] - 2024-06-12

- Add ahead of time compilation support for JRuby

## [0.1.6] - 2023-06-19

- Bugfix: Do not clone default gems, because they are already included in the jruby jars standard library

## [0.1.5] - 2023-06-15

- Bugfix: use minor ruby version without patch level for Gem files location

## [0.1.4] - 2023-04-28

- Jarbler also supports Gemfile references to Gems with git dependencies now

## [0.1.3] - 2023-04-25

- Removed .jruby-version so that the jruby version is not fixed anymore

## [0.1.2] - 2023-04-24

- extract valid Gem paths from Bundler instead of using the environment variable GEM_PATH

## [0.1.1] - 2023-04-24

- Fixed the bug 'java.lang.ClassNotFoundException: org.jruby.Main' with Windows

## [0.1.0] - 2023-04-12

- Initial release




