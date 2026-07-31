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
- `CooperConfig.Provider` now accepts `:dotenv`/`:dotenv_env`/
  `:dotenv_files`, passed straight through to `Cooper.load_file/2`
  (`cooper` 0.2.0's new `.env` file support).
- `CooperConfig.load!/2`, for loading a CASC file (`config/config.casc`
  by default) as the first line of your own application's
  `Application.start/2` -- the equivalent of `Provider` for `mix
  run`/`iex -S mix`/`mix test`, where `Config.Provider` never runs at
  all. Unlike `Provider`, this loads with `Cooper.load_file/2`'s default
  cache, since `:cooper` has already started by the time it's safe to
  call.

### Changed

- Bumped the `cooper` dependency to `~> 0.2.0`. `CooperConfig.Provider`
  now always loads with `cache: false` -- `cooper` 0.2.0 caches
  `Cooper.load_file/2` by default via a `Cooper.Cache` GenServer/ETS
  table started by `cooper`'s own OTP application, which isn't running
  yet when `Config.Provider` callbacks execute (they run before the
  release's own supervision tree starts, same reason a load failure
  raises instead of retrying -- see the moduledoc's "Errors" section);
  reaching for that cache here would crash, not just be pointless for a
  file read once per boot.
- Note for anyone passing `:env` explicitly: `cooper` 0.2.0 changed it
  from a full replacement of `System.get_env/0` to an override layer on
  top of it (see `cooper`'s own CHANGELOG for the full precedence
  chain) -- a `${...}` reference to a name not given an explicit `:env`
  entry now falls through to the real environment/`.env` files instead
  of being undefined.
