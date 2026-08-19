# CooperConfig

CooperConfig replaces Mix's own config sources (`config/runtime.exs`
via `Config.Provider` in a release; `config/config.exs`/`Application.
start/2` outside one) with a
[CASC](https://github.com/joetjen/cooper/blob/main/guides/casc/CASC.md)
file, loaded via [`cooper`](https://hex.pm/packages/cooper). It is a
thin bridge, not a parser: `Cooper.load_file/2` still does all the
actual work (lexing, imports, merging, `${...}`/`@{...}`/`%{...}`
resolution, secret-wrapping); `CooperConfig` only converts the result
into the shape `Application`/`Config.Provider` expect and plugs it into
either a release's boot sequence (`CooperConfig.Provider`) or your own
application's startup (`CooperConfig.load!/2`, see below).

```elixir
# config.casc
#@version = 1.0

my_app {
  port = 4000
  *password = ${DB_PASSWORD}
}
```

```elixir
# mix.exs
defp releases do
  [
    my_app: [
      config_providers: [
        {CooperConfig.Provider, path: "/etc/my_app/config.casc"}
      ]
    ]
  ]
end
```

At boot, the release reads `config.casc`, and `Application.get_env(:my_app,
:port)`/`Application.get_env(:my_app, :password)` return `4000` and the
real (revealed) value of `DB_PASSWORD` respectively — merged on top of
whatever `config/runtime.exs` (if any) already set, the same way a
second `config.exs` import merges on top of the first.

## Outside a release: `CooperConfig.load!/2`

`Provider` only runs as part of a `mix release` boot — `mix run`/`iex -S
mix`/`mix test` never invoke `Config.Provider` at all. For those, call
`CooperConfig.load!/2` as the first line of your own application's
`Application.start/2`:

```elixir
def start(_type, _args) do
  CooperConfig.load!()

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

By that point `:cooper` has already started as one of `cooper_config`'s
own dependencies, so — unlike `Provider`, which has to disable it —
this genuinely benefits from `Cooper.load_file/2`'s cache. In a release,
use both together: `Provider` gets the value in before anything could
miss it, and `load!/2` re-reads the same file through Cooper's cache
once it's safe to, overwriting `Provider`'s result (a no-op for an
unchanged file). See `CooperConfig.load!/2`'s own moduledoc for the full
tradeoff.

## Installation

Add `cooper_config` to your list of dependencies in `mix.exs`. `cooper`
comes along as its own dependency automatically — no separate line
needed:

```elixir
def deps do
  [
    {:cooper_config, "~> 0.1.0"}
  ]
end
```

## Options

`CooperConfig.Provider` and `CooperConfig.load!/2` both accept most of
what `Cooper.load_file/2` does (`:env`, `:resolvers`, `:tags`,
`:import_schemes`, `:dotenv`, `:dotenv_env`, `:dotenv_files`), plus
`:reveal_secrets` (default `true` — see `CooperConfig.Convert`'s
moduledoc for the tradeoff of turning it off) and `:secret_module`,
which reveals each secret and immediately re-wraps it in a type you own
(`SomeModule.new(value)`). That last one is for a codebase that already
has its own secret type and does not want a dependency's struct in its
configuration contracts: same leak protection as
`reveal_secrets: false`, but consuming code reveals through a type it
controls. It is a module rather than a function because these options
are written into a release's `sys.config`.

An option neither library recognizes raises rather than being ignored, so a
typo or a version older than the option fails at boot instead of quietly
doing nothing. `Provider` also raises on `:cache`/`:watch_env`, which it
cannot honour. `:env` is an override
layer, not a replacement — `System.get_env/0` (and any `.env` file) is
always consulted too, for any name not given an explicit entry.

`CooperConfig.Provider` additionally takes `:path` (required — a
literal string, `{:system, "ENV_VAR"}`, or `{:system, "ENV_VAR",
"/default"}`, same as `Config.Provider.resolve_config_path!/1`), and
never exposes `:cache`/`:watch_env` — it always loads with
`cache: false`, since `Config.Provider` callbacks run before `:cooper`'s
own OTP application (and `Cooper.Cache`'s process) has started.

`CooperConfig.load!/2` takes the CASC file's path as a plain argument
instead (defaulting to `config/config.casc`), and *does* expose
`:cache`/`:watch_env`, on top of `Cooper.load_file/2`'s own default
(`cache: true`) — see its moduledoc, or "Outside a release" above, for
why that's safe here but not in `Provider`.

## Where to go next

Links below go to [hexdocs.pm](https://hexdocs.pm/cooper_config), matching
the latest release. For docs built from the tip of `main` (including
unreleased changes), see the
[GitHub Pages preview](https://joetjen.github.io/cooper_config/), published
by [`docs.yml`](.github/workflows/docs.yml) on every push to `main`.

- **[`CooperConfig.Provider`](https://hexdocs.pm/cooper_config/CooperConfig.Provider.html)**
  — the `Config.Provider`, full option list, and error behavior.
- **[`CooperConfig.load!/2`](https://hexdocs.pm/cooper_config/CooperConfig.html#load!/2)**
  — the `Application.start/2`-time loader, cached, for use outside a
  release (or alongside `Provider` inside one).
- **[`CooperConfig.Convert`](https://hexdocs.pm/cooper_config/CooperConfig.Convert.html)**
  — the underlying map → app-config conversion, usable on its own.
- **[`cooper`](https://hexdocs.pm/cooper)** and its
  **[CASC reference](https://github.com/joetjen/cooper/blob/main/guides/casc/CASC.md)**
  — everything about the config language and the library that loads it.

## Development

```sh
mix deps.get
mix precommit
```

`mix precommit` runs everything a change needs to pass before review —
formatting, `--warnings-as-errors` compilation, Credo, Sobelow, the
test suite, and Dialyzer, in that order.

## License

MIT — see [LICENSE](LICENSE).
