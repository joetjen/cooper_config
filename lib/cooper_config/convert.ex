defmodule CooperConfig.Convert do
  @moduledoc """
  Converts a `Cooper.load_file/2`/`Cooper.load_string/2` result (a
  string-keyed map, CASC blocks nested arbitrarily deep) into the
  `[app: [key: value, ...]]` shape `Application` and `Config.Provider`
  expect.

  Each map -- at every nesting level, not just the top two -- becomes a
  keyword list with atom keys, so the result deep-merges against
  existing app config the same way multiple `config.exs` files merge
  (`Config.Reader.merge/2` only deep-merges when both sides are keyword
  lists; a plain map would replace wholesale instead). Lists and tuples
  are walked element-wise but keep their own shape; every other value
  (numbers, strings, atoms, booleans, `Cooper.IPv4`/`Cooper.IPv6`,
  duration/byte-size tuples, ...) passes through unchanged.

  ## Secrets

  A `Cooper.Secret`-wrapped value is revealed (`Cooper.Secret.reveal/1`)
  by default, since `Application`/release config has always held raw
  secrets in ordinary Mix config (`System.fetch_env!/1` in
  `runtime.exs`, for example) and most consumers of app env (`Ecto`,
  `Plug.SSL`, ...) expect a plain value, not a wrapped one. Pass
  `reveal_secrets: false` to keep values wrapped instead -- consuming
  code then needs `Cooper.Secret.reveal/1` at the point of use, trading
  drop-in compatibility for the same accidental-leak protection
  `Cooper` gives everywhere else.

  ## A note on atoms

  Every map key becomes an atom via `String.to_atom/1`, same posture as
  `Cooper`'s own handling of CASC atom literals (see its moduledoc):
  fine for config sourced from a fixed, trusted set of files, not
  something to point at untrusted input.
  """

  alias Cooper.Secret

  @type opts :: [reveal_secrets: boolean()]

  @doc """
  Converts `data` (a string-keyed map) into an app-config keyword list.

  ## Examples

      iex> CooperConfig.Convert.to_app_config(%{"my_app" => %{"port" => 4000}})
      [my_app: [port: 4000]]

      iex> CooperConfig.Convert.to_app_config(%{"my_app" => %{"password" => %Cooper.Secret{value: "hunter2"}}})
      [my_app: [password: "hunter2"]]

      iex> CooperConfig.Convert.to_app_config(
      ...>   %{"my_app" => %{"password" => %Cooper.Secret{value: "hunter2"}}},
      ...>   reveal_secrets: false
      ...> )
      [my_app: [password: %Cooper.Secret{value: "hunter2"}]]

  """
  @spec to_app_config(map(), opts()) :: keyword()
  def to_app_config(data, opts \\ []) when is_map(data) do
    normalize(data, Keyword.get(opts, :reveal_secrets, true))
  end

  defp normalize(%Secret{} = secret, true), do: normalize(Secret.reveal(secret), true)
  defp normalize(%Secret{} = secret, false), do: secret
  defp normalize(%_struct{} = value, _reveal_secrets?), do: value

  defp normalize(value, reveal_secrets?) when is_map(value) do
    Enum.map(value, fn {key, val} -> {String.to_atom(key), normalize(val, reveal_secrets?)} end)
  end

  defp normalize(value, reveal_secrets?) when is_list(value) do
    Enum.map(value, &normalize(&1, reveal_secrets?))
  end

  defp normalize(value, reveal_secrets?) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&normalize(&1, reveal_secrets?))
    |> List.to_tuple()
  end

  defp normalize(value, _reveal_secrets?), do: value
end
