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
    * `:dotenv`, `:dotenv_env`, `:dotenv_files`, `:dotenv_dir` -- `.env`
      file layering, on by default, read from the project root (in a
      release, `RELEASE_ROOT`) unless `:dotenv_dir` names another
      directory; see `Cooper.Dotenv` for the full rules. Omitted here
      means Cooper's own default applies.
    * `:modules` -- what a `!module("Name")` means, by the name exactly
      as written, before Cooper's own convention; see `Cooper`.

  `:cache`/`:watch_env` are deliberately **not** exposed -- `load/2`
  always calls `Cooper.load_file/2` with `cache: false`, and passing
  either one raises rather than being quietly disregarded. `Config.Provider`
  callbacks run before the release's own supervision tree starts, which
  is also what starts `:cooper`'s OTP application and, with it, the
  `Cooper.Cache` process the cache relies on -- caching here wouldn't
  just be pointless for a file read exactly once per boot, it would
  crash trying to reach a cache process that isn't running yet.

  Plus one option of its own:

    * `:secret_module` -- passed to `CooperConfig.Convert.to_app_config/2`;
      re-wraps each secret in a type you own rather than revealing it.
      An atom, because these options are written into the release's
      `sys.config`.
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
          dotenv_dir: String.t(),
          modules: %{optional(String.t()) => module()},
          reveal_secrets: boolean(),
          secret_module: module() | nil
        ]

  # Every option this provider understands. An option outside this set is
  # almost always a typo or a version skew, and silently ignoring it is the
  # worst possible outcome: passing `:secret_module` to a version that predates
  # it left secrets revealed in a release with no warning anywhere.
  @known_opts [
    :path,
    :env,
    :resolvers,
    :tags,
    :import_schemes,
    :dotenv,
    :dotenv_env,
    :dotenv_files,
    :dotenv_dir,
    :modules,
    :reveal_secrets,
    :secret_module
  ]

  @doc """
  Validates `opts` and builds the state `load/2` receives.

  Raises if `:path` is missing or fails
  `Config.Provider.validate_config_path!/1`, or if `opts` contains a key this
  provider does not understand -- a typo or a version that predates an option
  would otherwise be ignored silently, and a provider that quietly does less
  than you asked is worse than one that refuses to boot.
  """
  @impl true
  def init(opts) do
    validate_opts!(opts)
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
      dotenv_dir: Keyword.get(opts, :dotenv_dir),
      modules: Keyword.get(opts, :modules),
      reveal_secrets: Keyword.get(opts, :reveal_secrets, true),
      secret_module: Keyword.get(opts, :secret_module)
    }
  end

  # Refuses any option outside `@known_opts`, naming the offender and what is
  # accepted, since the likely cause is a typo or a dependency older than the
  # option being passed.
  defp validate_opts!(opts) do
    case Keyword.keys(opts) -- @known_opts do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "#{inspect(__MODULE__)} received unknown option(s): #{inspect(unknown)}. " <>
                "Supported options: #{inspect(@known_opts)}. If one of these was added in a " <>
                "newer cooper_config, check the version you have installed."
    end
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
        dotenv_files: state.dotenv_files,
        dotenv_dir: state.dotenv_dir,
        modules: state.modules
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
          CooperConfig.Convert.to_app_config(data,
            reveal_secrets: state.reveal_secrets,
            secret_module: state.secret_module
          )

        Config.Reader.merge(config, app_config)

      {:error, error} ->
        raise "failed to load CASC config from #{inspect(path)}:\n\n#{CooperConfig.format_error(error)}"
    end
  end
end
