# Copilot Instructions for Jarbler

## What This Project Does

Jarbler is a Ruby gem that packages Ruby/Rails applications into self-executing JAR files. It bundles the app, JRuby runtime, and all gem dependencies into a single JAR runnable via `java -jar`. It is a modern alternative to Warbler.

## Commands

```bash
# Run all tests
bundle exec rake test

# Run a single test file
bundle exec ruby -Ilib -Itest test/jarbler/builder_test.rb

# Run a single test by name
bundle exec ruby -Ilib -Itest test/jarbler/builder_test.rb -n test_name_here

# Build the gem
bundle exec rake build

# Release the gem
bundle exec rake release
```

Enable verbose debug output for any command by setting `DEBUG=true`.

## Architecture

The build pipeline runs in three phases:

1. **Config** (`lib/jarbler/config.rb`): Reads `config/jarble.rb` (DSL block yielding a `Jarbler::Config` instance) or falls back to defaults. Auto-detects JRuby version from `.ruby-version` or fetches the latest `jruby-jars` gem version from RubyGems.org.

2. **Builder** (`lib/jarbler/builder.rb`): Creates a temp staging directory, copies jruby JARs, compiles `JarMain.java`, copies app files from `config.includes`, resolves gem dependencies from `Gemfile.lock`, then assembles everything into the final JAR with `jar` command. The staging dir is preserved when `DEBUG=true`.

3. **JarMain** (`lib/jarbler/JarMain.java`): A Java bootstrap class compiled and embedded in the JAR. It extracts the app into a temp directory at runtime and launches JRuby.

Entry points:
- `bin/jarble` CLI → `Jarbler.run` (build) or `Jarbler.config` (generate `config/jarble.rb` template)
- `lib/jarbler.rb` exposes `Jarbler.run` and `Jarbler.config`

## Key Conventions

- **Config DSL**: `config/jarble.rb` must return a `Jarbler::Config` instance from a block: `Jarbler::Config.new do |config| ... end`. The file is `eval`'d directly.
- **`compile_java_version` is deprecated**: Use `config.java_opts = '-source X -target X'` instead. The config validator raises if `compile_java_version` is set.
- **Gem path layout inside JAR**: Gems land under `gems/` with a suffix of `jruby/<ruby_minor_version>` (patch set to 0). `excludes_from_compile` paths map to this final JAR layout (e.g., `app_root/app/models`, `gems`).
- **Test helpers** (`test/test_helper.rb`): Tests extend `Minitest::Test` with `log`, `debug`, and `exec_and_log` (wraps `Open3.capture3`). Use `jruby_version_test_config_line` to get a Java-version-compatible JRuby version string for test configs.
- **No runtime gem dependencies**: The gemspec declares zero runtime dependencies; only stdlib and JRuby-bundled jars are used at runtime.
- **`DEBUG` env var**: Controls verbose logging across both the gem code and tests (`puts msg if ENV['DEBUG']`).
