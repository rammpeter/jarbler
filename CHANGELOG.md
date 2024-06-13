## [Unreleased]

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




