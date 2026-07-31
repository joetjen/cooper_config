defmodule CooperConfig do
  @moduledoc """
  A companion to [`cooper`](https://hex.pm/packages/cooper): loads app
  config from a CASC file instead of `config/runtime.exs`.

  `cooper_config` doesn't parse or resolve anything itself -- that's
  entirely `Cooper.load_file/2`'s job. It only bridges the result of
  that call into the shape `Application`/`Config.Provider` expect:

    * `CooperConfig.Provider` -- a `Config.Provider` your release's
      `mix.exs` points at, so a CASC file is read and merged into app
      config at boot, the same slot `Config.Reader` (`runtime.exs`)
      normally fills.
    * `CooperConfig.Convert` -- the underlying map -> app-config
      conversion, exposed on its own for callers who already have a
      `Cooper.load_file/2` result and want the same conversion without
      going through a release boot.

  See `CooperConfig.Provider`'s moduledoc for the `mix.exs` wiring and
  a full example.
  """
end
