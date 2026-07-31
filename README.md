# CooperConfig

CooperConfig replaces Mix's default release-time config source
(`config/runtime.exs`, read by `Config.Reader`) with a
[CASC](https://github.com/joetjen/cooper/blob/main/guides/casc/CASC.md)
file, loaded via [`cooper`](https://hex.pm/packages/cooper). It is a
thin bridge, not a parser: `Cooper.load_file/2` still does all the
actual work (lexing, imports, merging, `${...}`/`@{...}`/`%{...}`
resolution, secret-wrapping); `CooperConfig` only converts the result
into the shape `Application`/`Config.Provider` expect and plugs it into
a release's boot sequence.

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

`CooperConfig.Provider` takes `:path` (required — a literal string,
`{:system, "ENV_VAR"}`, or `{:system, "ENV_VAR", "/default"}`, same as
`Config.Provider.resolve_config_path!/1`), plus everything
`Cooper.load_file/2` accepts (`:env`, `:resolvers`, `:tags`,
`:import_schemes`), plus `:reveal_secrets` (default `true` — see
`CooperConfig.Convert`'s moduledoc for the tradeoff of turning it off).

## Where to go next

- **[`CooperConfig.Provider`](https://hexdocs.pm/cooper_config/CooperConfig.Provider.html)**
  — the `Config.Provider`, full option list, and error behavior.
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
