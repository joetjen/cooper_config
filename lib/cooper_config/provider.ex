defmodule CooperConfig.Provider do
  @moduledoc """
  A `Config.Provider` that loads a CASC file via `Cooper.load_file/2`
  and merges it into the release's app config at boot -- the same slot
  `Config.Reader` (`config/runtime.exs`) normally fills.

  ## Usage

  Point a release at it in `mix.exs`:

      def project do
        [
          ...,
          releases: releases()
        ]
      end

      defp releases do
        [
          my_app: [
            config_providers: [
              {CooperConfig.Provider, path: "/etc/my_app/config.casc"}
            ]
          ]
        ]
      end

  `:path` accepts anything `Config.Provider.resolve_config_path!/1`
  does -- a literal string, `{:system, "ENV_VAR"}`, or `{:system,
  "ENV_VAR", "/default/path"}` -- so the path itself can come from the
  environment.

  ## Options

  Besides `:path` (required), every other option is passed straight
  through to `Cooper.load_file/2` -- see its moduledoc for what each
  one does:

    * `:env` -- defaults to `Cooper.load_file/2`'s own default
      (`System.get_env/0`) if omitted.
    * `:resolvers`, `:tags`, `:import_schemes` -- default to `%{}`.

  Plus one option of its own:

    * `:reveal_secrets` -- passed to `CooperConfig.Convert.to_app_config/2`,
      see its moduledoc for the tradeoff. Defaults to `true`.

  ## Errors

  A load failure (unreadable file, parse/resolve error, ...) raises --
  `Config.Provider` callbacks run before the release's supervision tree
  starts, so there's no supervisor to catch and restart from, and
  booting further with incomplete config is worse than not booting.
  """

  @behaviour Config.Provider

  @type opts :: [
          path: Config.Provider.config_path(),
          env: %{optional(String.t()) => String.t()},
          resolvers: %{optional(String.t()) => (String.t() -> {:ok, term()} | {:error, term()})},
          tags: %{optional(String.t()) => (term() -> {:ok, term()} | {:error, term()})},
          import_schemes: %{
            optional(String.t()) => (String.t() -> {:ok, String.t()} | {:error, term()})
          },
          reveal_secrets: boolean()
        ]

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    Config.Provider.validate_config_path!(path)

    %{
      path: path,
      env: Keyword.get(opts, :env),
      resolvers: Keyword.get(opts, :resolvers, %{}),
      tags: Keyword.get(opts, :tags, %{}),
      import_schemes: Keyword.get(opts, :import_schemes, %{}),
      reveal_secrets: Keyword.get(opts, :reveal_secrets, true)
    }
  end

  @impl true
  def load(config, state) do
    path = Config.Provider.resolve_config_path!(state.path)

    cooper_opts =
      [
        env: state.env,
        resolvers: state.resolvers,
        tags: state.tags,
        import_schemes: state.import_schemes
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Cooper.load_file(path, cooper_opts) do
      {:ok, data} ->
        app_config =
          CooperConfig.Convert.to_app_config(data, reveal_secrets: state.reveal_secrets)

        Config.Reader.merge(config, app_config)

      {:error, error} ->
        raise "failed to load CASC config from #{inspect(path)}:\n\n#{format_error(error)}"
    end
  end

  defp format_error(errors) when is_list(errors),
    do: Enum.map_join(errors, "\n", &Ichor.Error.format/1)

  defp format_error(error), do: Ichor.Error.format(error)
end
