defmodule Mix.Tasks.Cooper.Load do
  @moduledoc """
  Loads a CASC document into the application environment, before Mix starts
  anything.

  This exists for the gap `Config.Provider` does not cover. A provider runs in a
  release, before any application starts; under Mix there is no such hook, so a
  library that validates its configuration when it starts has nowhere to read it
  from once `config/*.exs` is gone.

  Run it ahead of whichever task starts applications, in the same invocation:

      # mix.exs
      aliases: [
        test: ["cooper.load", "test"],
        run: ["cooper.load", "run"]
      ]

  Both run in one VM, so the configuration this applies is already in place when
  the following task starts applications. A consuming project therefore needs no
  `Application` module, no supervision child and no manual
  `Application.ensure_all_started/1` — the same arrangement a release gets from
  its provider.

  ## Options

    * `--path` — the document to load, `config/config.casc` by default,
      resolved from the project root rather than the working directory.
    * `--secret-module` — wraps each secret in that module (see
      `CooperConfig.Convert`), rather than revealing it.

  `MIX_ENV` is passed to the document as an environment variable, because Mix
  does not export it. That is what makes `import "env/${MIX_ENV:dev}.casc"`
  select the right overlay under `mix test` and `mix run` alike.

  Caching is off: a Mix task runs before `:cooper`'s own application, so the
  cache's ETS table does not exist yet, and a document read once per invocation
  has nothing to gain from it.
  """

  use Mix.Task

  @shortdoc "Loads a CASC document into the application environment"

  @default_path "config/config.casc"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(arguments) do
    # The dependency code path is not loaded when a task runs this early, and
    # `CooperConfig` itself lives there.
    Mix.Task.run("loadpaths")

    {options, _rest} =
      OptionParser.parse!(arguments, strict: [path: :string, secret_module: :string])

    path = Path.expand(options[:path] || @default_path, File.cwd!())

    CooperConfig.load!(path, load_options(options))
  end

  # Builds the loader options, passing the build environment through so an
  # `${MIX_ENV}` reference in the document resolves.
  @spec load_options(keyword()) :: keyword()
  defp load_options(options) do
    base = [cache: false, env: %{"MIX_ENV" => to_string(Mix.env())}]

    case options[:secret_module] do
      nil -> base
      module -> Keyword.put(base, :secret_module, Module.concat([module]))
    end
  end
end
