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

    * `:env` -- an override layer, not a replacement: `System.get_env/0`
      (and any `.env` file, see `:dotenv` below) is always consulted
      too, for any name not given an explicit entry here. Defaults to
      `Cooper.load_file/2`'s own default (nothing extra layered on top
      of `System.get_env/0`/`.env`) if omitted.
    * `:resolvers`, `:tags`, `:import_schemes` -- default to `%{}`.
    * `:dotenv`, `:dotenv_env`, `:dotenv_files` -- `.env` file layering,
      on by default; see `Cooper.Dotenv` for the full rules. Omitted
      here means Cooper's own default applies.

  `:cache`/`:watch_env` are deliberately **not** exposed -- `load/2`
  always calls `Cooper.load_file/2` with `cache: false`. `Config.Provider`
  callbacks run before the release's own supervision tree starts, which
  is also what starts `:cooper`'s OTP application and, with it, the
  `Cooper.Cache` process the cache relies on -- caching here wouldn't
  just be pointless for a file read exactly once per boot, it would
  crash trying to reach a cache process that isn't running yet.

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
          dotenv: boolean(),
          dotenv_env: atom() | nil,
          dotenv_files: [String.t()],
          reveal_secrets: boolean()
        ]

  @doc """
  Validates `opts` and builds the state `load/2` receives.

  Raises if `:path` is missing or fails
  `Config.Provider.validate_config_path!/1`.
  """
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
      dotenv: Keyword.get(opts, :dotenv),
      dotenv_env: Keyword.get(opts, :dotenv_env),
      dotenv_files: Keyword.get(opts, :dotenv_files),
      reveal_secrets: Keyword.get(opts, :reveal_secrets, true)
    }
  end

  @doc """
  Loads the CASC file described by `state` (as built by `init/1`) and
  merges it into `config` via `Config.Reader.merge/2`.

  Raises if the file can't be read, parsed, or resolved -- see the
  moduledoc's "Errors" section.
  """
  @impl true
  def load(config, state) do
    path = Config.Provider.resolve_config_path!(state.path)

    cooper_opts =
      [
        env: state.env,
        resolvers: state.resolvers,
        tags: state.tags,
        import_schemes: state.import_schemes,
        dotenv: state.dotenv,
        dotenv_env: state.dotenv_env,
        dotenv_files: state.dotenv_files
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      # `Config.Provider` callbacks run before `:cooper`'s own OTP
      # application -- and `Cooper.Cache`'s GenServer/ETS table -- has
      # started (see the moduledoc's "Options" section), so caching
      # here isn't just useless for a file read once per boot, it's a
      # crash waiting to happen. Not user-overridable.
      |> Keyword.put(:cache, false)

    case Cooper.load_file(path, cooper_opts) do
      {:ok, data} ->
        app_config =
          CooperConfig.Convert.to_app_config(data, reveal_secrets: state.reveal_secrets)

        Config.Reader.merge(config, app_config)

      {:error, error} ->
        raise "failed to load CASC config from #{inspect(path)}:\n\n#{CooperConfig.format_error(error)}"
    end
  end
end
