defmodule CooperConfig.ConvertTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CooperConfig.Convert

  # Stands in for a consuming codebase's own secret type -- the reason
  # `:secret_module` exists is that such a codebase does not want a
  # dependency's struct in its configuration contracts. Deliberately not a
  # `Cooper.Secret` clone: it has no `:redacted` field, because partial
  # redaction is a CASC concern that a consumer's own type need not model.
  defmodule OwnedSecret do
    @moduledoc false
    @enforce_keys [:value]
    defstruct [:value]

    # `new/1` is the whole contract `:secret_module` requires. A real consumer
    # type would also redact through `Inspect`; that is its own business and is
    # not asserted here (protocols are already consolidated by test time).
    def new(value), do: %__MODULE__{value: value}
  end

  doctest CooperConfig.Convert

  describe "to_app_config/2" do
    test "converts a flat block into a keyword list under the app name" do
      assert Convert.to_app_config(%{"my_app" => %{"port" => 4000}}) == [my_app: [port: 4000]]
    end

    test "converts nested blocks into nested keyword lists at every level" do
      data = %{"my_app" => %{"repo" => %{"pool" => %{"size" => 10}}}}
      assert Convert.to_app_config(data) == [my_app: [repo: [pool: [size: 10]]]]
    end

    test "walks lists element-wise but keeps them as lists" do
      data = %{"my_app" => %{"hosts" => [%{"name" => "a"}, %{"name" => "b"}]}}
      assert Convert.to_app_config(data) == [my_app: [hosts: [[name: "a"], [name: "b"]]]]
    end

    test "walks tuples element-wise but keeps them as tuples" do
      data = %{"my_app" => %{"pair" => {%{"a" => 1}, "b"}}}
      assert Convert.to_app_config(data) == [my_app: [pair: {[a: 1], "b"}]]
    end

    test "passes scalars through unchanged" do
      data = %{
        "my_app" => %{"a" => 1, "b" => 1.5, "c" => "s", "d" => true, "e" => nil, "f" => :atom}
      }

      assert Convert.to_app_config(data) == [
               my_app: [a: 1, b: 1.5, c: "s", d: true, e: nil, f: :atom]
             ]
    end

    test "passes non-Secret structs through unchanged" do
      date = ~D[2026-09-30]
      assert Convert.to_app_config(%{"my_app" => %{"date" => date}}) == [my_app: [date: date]]
    end
  end

  describe "to_app_config/2 with typed literals" do
    test "turns a byte size into an integer number of bytes" do
      assert app_value("size = 1GiB") == 1_073_741_824
      assert app_value("size = 512KB") == 512_000
    end

    test "turns a duration into integer milliseconds" do
      assert app_value("timeout = 14d") == 1_209_600_000
      assert app_value("timeout = 500ms") == 500
      assert app_value("timeout = 2000us") == 2
    end

    test "rejects a duration that is not a whole number of milliseconds" do
      assert_raise ArgumentError, ~r/1500000ns is not a whole number of milliseconds/, fn ->
        app_value("timeout = 1500us")
      end
    end

    test "turns an IP address into an :inet tuple" do
      assert app_value("ip = 10.0.0.1") == {10, 0, 0, 1}
      assert app_value("ip = ::1") == {0, 0, 0, 0, 0, 0, 0, 1}
    end

    test "turns a CIDR block into an {address, prefix} pair" do
      assert app_value("ip = 10.0.0.0/8") == {{10, 0, 0, 0}, 8}
      assert app_value("ip = fd00::/8") == {{0xFD00, 0, 0, 0, 0, 0, 0, 0}, 8}
    end

    test "converts typed literals nested in lists and variables" do
      assert app_value("sizes = [1KiB, 2KiB]") == [1024, 2048]
      assert app_value("size = @{limit}", "@*limit = 1GiB") == 1_073_741_824
    end

    test "converts the tagged values directly" do
      data = %{"my_app" => %{"b" => {:bytes, 8}, "d" => {:duration, 3_000_000}}}
      assert Convert.to_app_config(data) == [my_app: [b: 8, d: 3]]
    end

    test "reveals a Cooper.Secret by default" do
      data = %{"my_app" => %{"password" => %Cooper.Secret{value: "hunter2"}}}
      assert Convert.to_app_config(data) == [my_app: [password: "hunter2"]]
    end

    test "reveal_secrets: false keeps the Cooper.Secret wrapper" do
      secret = %Cooper.Secret{value: "hunter2"}
      data = %{"my_app" => %{"password" => secret}}
      assert Convert.to_app_config(data, reveal_secrets: false) == [my_app: [password: secret]]
    end

    test "secret_module: re-wraps a Cooper.Secret in the consumer's own type" do
      data = %{"my_app" => %{"password" => %Cooper.Secret{value: "hunter2"}}}

      assert Convert.to_app_config(data, secret_module: OwnedSecret) ==
               [my_app: [password: %OwnedSecret{value: "hunter2"}]]
    end

    test "secret_module: leaves non-secret values completely alone" do
      data = %{"my_app" => %{"port" => 4000, "password" => %Cooper.Secret{value: "hunter2"}}}

      assert [my_app: [password: %OwnedSecret{}, port: 4000]] =
               Convert.to_app_config(data, secret_module: OwnedSecret)
    end

    test "secret_module: takes precedence over reveal_secrets" do
      # Both spellings ask for something; the wrapper wins, so a caller that
      # names its own type cannot accidentally get a plain string.
      data = %{"my_app" => %{"password" => %Cooper.Secret{value: "hunter2"}}}

      assert Convert.to_app_config(data, secret_module: OwnedSecret, reveal_secrets: true) ==
               [my_app: [password: %OwnedSecret{value: "hunter2"}]]
    end

    test "secret_module: nil is the documented default and changes nothing" do
      data = %{"my_app" => %{"password" => %Cooper.Secret{value: "hunter2"}}}

      assert Convert.to_app_config(data, secret_module: nil) == Convert.to_app_config(data)
    end

    test "secret_module: normalizes the value inside the secret before wrapping" do
      # A secret holding a block is unusual, but the value still has to be
      # converted like any other -- wrapping must not skip that.
      data = %{"my_app" => %{"creds" => %Cooper.Secret{value: %{"user" => "root"}}}}

      assert Convert.to_app_config(data, secret_module: OwnedSecret) ==
               [my_app: [creds: %OwnedSecret{value: [user: "root"]}]]
    end

    test "handles multiple top-level apps" do
      data = %{"app_a" => %{"x" => 1}, "app_b" => %{"y" => 2}}
      assert Convert.to_app_config(data) == [app_a: [x: 1], app_b: [y: 2]]
    end
  end

  describe "property: hiding then revealing matches revealing directly" do
    property "reveal_secrets: false followed by revealing every wrapper equals reveal_secrets: true" do
      check all(top <- top_level_gen()) do
        revealed = Convert.to_app_config(top, reveal_secrets: true)
        hidden = Convert.to_app_config(top, reveal_secrets: false)

        assert reveal_all(hidden) == revealed
      end
    end

    property "secret_module: wrapping then unwrapping equals reveal_secrets: true" do
      # The invariant that matters for a consumer swapping its own type in:
      # re-wrapping must lose nothing and change nothing but the wrapper.
      check all(top <- top_level_gen()) do
        revealed = Convert.to_app_config(top, reveal_secrets: true)
        owned = Convert.to_app_config(top, secret_module: OwnedSecret)

        assert unwrap_all(owned) == revealed
      end
    end
  end

  defp top_level_gen do
    StreamData.map_of(key_gen(), value_gen(), min_length: 1, max_length: 3)
  end

  defp key_gen, do: StreamData.string(:alphanumeric, min_length: 1, max_length: 6)

  defp scalar_gen do
    StreamData.one_of([
      StreamData.integer(),
      StreamData.boolean(),
      StreamData.string(:alphanumeric),
      StreamData.constant(nil)
    ])
  end

  # `Cooper.Secret` only ever wraps a leaf value (CASC.md §4.3) -- never
  # a block -- so the generator mirrors that instead of nesting secrets
  # inside secrets, which real `Cooper` output never produces.
  defp secret_gen, do: StreamData.map(scalar_gen(), &%Cooper.Secret{value: &1})

  defp value_gen do
    leaf = StreamData.one_of([scalar_gen(), secret_gen()])

    StreamData.tree(leaf, fn child ->
      StreamData.one_of([
        StreamData.map_of(key_gen(), child, max_length: 3),
        StreamData.list_of(child, max_length: 3)
      ])
    end)
  end

  defp reveal_all(%Cooper.Secret{} = secret), do: Cooper.Secret.reveal(secret)

  defp reveal_all(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.map(value, fn {key, val} -> {key, reveal_all(val)} end)
    else
      Enum.map(value, &reveal_all/1)
    end
  end

  defp reveal_all(value), do: value

  defp unwrap_all(%OwnedSecret{value: value}), do: unwrap_all(value)

  defp unwrap_all(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.map(value, fn {key, val} -> {key, unwrap_all(val)} end)
    else
      Enum.map(value, &unwrap_all/1)
    end
  end

  defp unwrap_all(value), do: value

  # Loads a one-block CASC document and returns the single value it sets.
  defp app_value(body, preamble \\ "") do
    {:ok, data} =
      Cooper.load_string("#@version = 1.0\n" <> preamble <> "\nmy_app {\n" <> body <> "\n}\n")

    [my_app: [{_key, value}]] = Convert.to_app_config(data)
    value
  end
end
