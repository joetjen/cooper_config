# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Needs Cooper 0.6, released first; until then the dependency is the
Cooper checkout beside this one.

### Added

- **`:dotenv_dir`** on `load!/2` and `CooperConfig.Provider` -- where
  Cooper reads `.env` files from, when not the project root (in a
  release, `RELEASE_ROOT`), which is Cooper's own default.
- **`:modules`** on both -- what a `!module("Name")` means, by the name
  as written, before Cooper's own convention. Both options were refused
  as unknown.

## [0.3.0] - 2026-10-01

### Added

- `mix cooper.load`, which applies a CASC document to the application
  environment before Mix starts anything:

      aliases: [test: ["cooper.load", "test"]]

  `Config.Provider` covers a release, running before any application starts.
  Under Mix there is no such hook, so a library that validates its configuration
  at start had nowhere to read it from once `config/*.exs` was gone -- a
  `test_helper.exs` runs after Mix has already started it. Both tasks run in one
  VM, so the configuration is in place before the following task starts
  applications, and a consuming project needs no `Application` module,
  supervision child or manual `Application.ensure_all_started/1`.

  It passes `MIX_ENV` to the document, since Mix does not export it, which is
  what lets an `env/${MIX_ENV:dev}.casc` import resolve. `--path` selects a
  different document; `--secret-module` wraps secrets rather than revealing
  them.

  Requires Cooper 0.4.0 for interpolated import paths.

### Changed

- **BREAKING (behaviour):** typed CASC literals now reach application
  configuration as plain values instead of `Cooper`'s tagged forms. A byte size
  (`1GiB`) becomes an integer number of bytes, a duration (`14d`) an integer
  number of milliseconds, an IP address the `:inet` tuple and a CIDR block an
  `{address, prefix}` pair. Code reading app env knows nothing about `Cooper`,
  so `{:bytes, n}` failed an ordinary `is_integer/1` check -- Hreinn's
  `max_object_bytes = 1GiB` was refused by `ASCO.S3.Config` that way. A duration
  that is not a whole number of milliseconds (`1500us`) raises `ArgumentError`
  rather than being rounded.
- Requires `cooper ~> 0.4` (was `~> 0.3`). `mix cooper.load` selects the
  environment overlay with Cooper 0.4's interpolated import paths and
  `!module` tag.

### Documentation

- Documented the per-environment overlay pattern
  (`import "env/${MIX_ENV:dev}.casc"`) in the README, including the three
  things that make it work: defaulting to `dev`, because Mix does not export
  `MIX_ENV` and a plain `mix run` is the only case the default has to cover;
  keeping a file present for every selectable value, since a missing import is
  a load error; and importing the overlay last so it overrides rather than is
  overridden.

  Requires Cooper 0.4.0, which allows `${...}` in an import path.

## [0.2.0] - 2026-08-19

### Changed

- **BREAKING (behaviour):** `CooperConfig.Provider.init/1` and
  `CooperConfig.load!/2` now raise `ArgumentError` on an option they do not
  recognize, instead of ignoring it.

  Neither this library nor Cooper rejected unknown keys, so a typo meant the
  option simply did not happen. That was found the hard way: passing
  `:secret_module` to a version predating it produced a release whose secrets
  were revealed, with no warning anywhere. A provider that quietly does less
  than you asked is worse than one that refuses to boot.

  This also affects `:cache` and `:watch_env` on `Provider`, which were
  previously accepted and disregarded — the provider always loads with
  `cache: false`, because `Cooper.Cache`'s process has not started when a
  provider runs. Passing either now raises rather than silently doing the
  opposite of what was asked.

  The accepted list is enumerated in each module, which couples it to Cooper's
  own option set: an option added there needs adding here. That is deliberate —
  raising on a valid-but-newer option is loud and immediately diagnosable, while
  ignoring a security-relevant one is neither.

### Added

- `:secret_module`, accepted by `CooperConfig.Convert.to_app_config/2`,
  `CooperConfig.load!/2` and `CooperConfig.Provider`. Each `Cooper.Secret` is
  revealed and immediately re-wrapped as `secret_module.new(value)`.

  This is for a codebase that already owns a secret type and does not want a
  dependency's struct appearing in its own configuration contracts. It gets the
  same accidental-leak protection as `reveal_secrets: false`, while consuming
  code reveals through a type it controls.

  It takes precedence over `:reveal_secrets`, so a caller that names its own
  type cannot accidentally receive a plain string. It is a module rather than a
  function because these options are written into a release's `sys.config`,
  where an atom round-trips dependably and a captured function does not.

  Defaults to `nil`, which leaves existing behaviour exactly as it was.

- Docs are now also published to
  [GitHub Pages](https://joetjen.github.io/cooper_config/) on every push to
  `main` (`.github/workflows/docs.yml`), as an unreleased-changes preview
  alongside the release docs on hexdocs.pm.

### Changed

- `mix.exs`'s `docs()` now sets `canonical: "https://hexdocs.pm/cooper_config"`,
  so the GitHub Pages copy doesn't compete with hexdocs.pm as duplicate
  content.

## [0.1.1] - 2026-08-03

### Changed

- Bumped the `cooper` dependency to `~> 0.2` (from `~> 0.2.0`), picking
  up `cooper` 0.2.2, which in turn requires `ichor_runtime ~> 0.2`
  (from `~> 0.1.0`). `ichor_runtime` 0.2.0's breaking change (raw
  capture data is now an ordered `[{name, value}]` list instead of a
  plain map, fixing sibling-capture evaluation order) is internal to
  `mix ichor.gen`-generated parser code; `cooper` 0.2.2 already
  regenerated its own grammar modules to match. `cooper_config` never
  touches raw captures itself -- it only calls `Cooper.load_file/2`'s
  public API and `Ichor.Error.format/1` -- so there's no observable
  behavior change here.

## [0.1.0] - 2026-07-31

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
