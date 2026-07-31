# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `CooperConfig.Provider`, a `Config.Provider` implementation that
  loads a CASC file via `Cooper.load_file/2` at release boot and
  merges it into the release's app config, replacing
  `config/runtime.exs` for the settings it covers.
- `CooperConfig.Convert.to_app_config/2`, converting a `Cooper`-loaded
  value (string-keyed maps) into the `[app: [key: value, ...]]` shape
  `Application`/`Config.Provider` expect, deep-converting nested maps
  into keyword lists so `Config.Reader.merge/2` can merge them against
  existing config the same way multiple `config.exs` files merge.
