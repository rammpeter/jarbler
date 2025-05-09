## [Unreleased]


## [0.4.0] - 2025-04-24

- config attribute `compile_java_version` removed and replaced by 'java_opts'
- new config attribute `java_opts` allows to set additional options for the Java compiler used for jar file bootstrap code
- `java_opts` does not affect the optional AOT compilation of Ruby files.
- new config attribute `jrubyc_opts` allows to set additional options for JRuby's AOT compiler used for compilation of Ruby files

## [0.3.6] - 2025-03-31

- remove temporary folder with extracted jar content after termination of Ruby code even if Ruby code terminates the JVM hard with 'exit' or 'System.exit'
- provide exit code of Ruby code as exit code of the jar file execution

## [0.3.5] - 2025-03-22

- new config attribute "config.compile_java_version" allows control of setting for "javac -source and -target" for AOT compilation
- fix typo with smart quotes in config.rb

## [0.3.4] - 2025-03-07

- Warning if Ruby-specific environment variables (GEM_HOME etc.) are set which may cause malfunction of  app in jar file
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




