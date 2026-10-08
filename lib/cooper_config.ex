defmodule CooperConfig do
  @moduledoc """
  A companion to [`cooper`](https://hex.pm/packages/cooper): loads app
  config from a CASC file instead of `config/config.exs`/`runtime.exs`.

  `cooper_config` doesn't parse or resolve anything itself -- that's
  entirely `Cooper.load_file/2`'s job. It only bridges the result of
  that call into the shape `Application`/`Config.Provider` expect:

    * `CooperConfig.Provider` -- a `Config.Provider` your release's
      `mix.exs` points at, so a CASC file is read and merged into app
      config at boot, the same slot `Config.Reader` (`runtime.exs`)
      normally fills. Runs before anything in the release has started
      -- including `:cooper` itself -- so it always loads with
      `cache: false`.
    * `load!/2` -- meant to run as the first line of your own
      `Application.start/2`, once `:cooper` (a dependency of
      `cooper_config`) has already started as part of the normal OTP
      boot order. Unlike `Provider`, this genuinely benefits from
      `Cooper.load_file/2`'s default cache. Not a substitute for
      `Provider` in a release -- see `load!/2`'s own doc for how the
      two combine.
    * `CooperConfig.Convert` -- the underlying map -> app-config
      conversion both of the above are built on, exposed on its own for
      callers who already have a `Cooper.load_file/2` result and want
      the same conversion without going through either.

  See `CooperConfig.Provider`'s moduledoc for the `mix.exs` wiring and
  a full example.
  """

  @type opts :: [
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
          cache: boolean(),
          watch_env: boolean(),
          root: String.t(),
          dotenv_override: boolean(),
          reveal_secrets: boolean(),
          secret_module: module() | nil
        ]

  # This library's own options, plus every option it forwards to
  # `Cooper.load_file/2`. Enumerated so a typo or an option from a newer
  # version raises here instead of being silently dropped -- neither this
  # library nor Cooper rejects an unknown key on its own, and a `:secret_module`
  # that quietly does nothing leaves secrets revealed with no warning.
  #
  # This does couple the list to Cooper's option set: an option added there
  # needs adding here too. That is deliberate. Raising on a valid-but-newer
  # option is loud and immediately diagnosable; ignoring a security-relevant one
  # is neither.
  @known_opts [
    :env,
    :dotenv,
    :dotenv_env,
    :dotenv_files,
    :dotenv_dir,
    :dotenv_override,
    :cache,
    :watch_env,
    :root,
    :resolvers,
    :tags,
    :import_schemes,
    :modules,
    :reveal_secrets,
    :secret_module
  ]

  @doc """
  Loads a CASC file -- `config/config.casc` (relative to `File.cwd!/0`,
  mirroring Mix's own `config/` convention) by default -- and merges it
  into already-running `Application` config, overwriting whatever's
  already set for the same keys (`Application.put_all_env/2`, same as
  Mix itself uses to apply `config.exs`/`runtime.exs`).

  Meant to be called as the very first line of your own application's
  `Application.start/2`, before building its supervision tree. By that
  point `:cooper` -- a dependency of `cooper_config` -- has already
  started as part of the normal OTP boot order, so, unlike
  `CooperConfig.Provider` (which has to force `cache: false`, see its
  moduledoc), this genuinely benefits from `Cooper.load_file/2`'s
  default cache: fast repeat calls across `iex -S mix` reloads, `mix
  test` runs in the same VM, or a later manual reload elsewhere in your
  app.

  This is *not* a substitute for `CooperConfig.Provider` in a `mix
  release` -- `Provider`'s guarantee (nothing in the release has
  started yet) still matters for any other dependency that reads
  `Application` config during its own boot, earlier than your app's
  `start/2` runs. Use both together for a release: `Provider` gets the
  value in before anything could miss it (necessarily a full reparse,
  `cache: false`); this then re-reads the same file -- now safely
  through Cooper's cache -- and overwrites `Provider`'s result with it,
  a no-op change in value for an unchanged file, which also primes the
  cache for whatever reads the file again later.

  Every option `Cooper.load_file/2` accepts is supported, plus
  `:reveal_secrets` (see `CooperConfig.Convert`'s moduledoc for the
  tradeoff), defaulting to `true`, and `:secret_module`, which re-wraps
  each secret in a type you own instead. An unrecognized option raises
  rather than being ignored. Raises on a load failure -- same
  reasoning as `CooperConfig.Provider`: continuing to boot with
  incomplete config is worse than not booting.
  """
  @spec load!(String.t(), opts()) :: :ok
  def load!(path \\ "config/config.casc", opts \\ []) do
    validate_opts!(opts)
    {convert_opts, cooper_opts} = Keyword.split(opts, [:reveal_secrets, :secret_module])

    case Cooper.load_file(path, cooper_opts) do
      {:ok, data} ->
        data
        |> CooperConfig.Convert.to_app_config(convert_opts)
        |> apply_config()

        :ok

      {:error, error} ->
        raise "failed to load CASC config from #{inspect(path)}:\n\n#{format_error(error)}"
    end
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
              "CooperConfig.load!/2 received unknown option(s): #{inspect(unknown)}. " <>
                "Supported options: #{inspect(@known_opts)}. If one of these was added in a " <>
                "newer cooper/cooper_config, check the versions you have installed."
    end
  end

  defp apply_config(app_config) do
    current = for {app, _kv} <- app_config, do: {app, Application.get_all_env(app)}
    merged = Config.Reader.merge(current, app_config)
    Application.put_all_env(merged, persistent: true)
  end

  @doc false
  def format_error(errors) when is_list(errors),
    do: Enum.map_join(errors, "\n", &Ichor.Error.format/1)

  def format_error(error), do: Ichor.Error.format(error)
end
