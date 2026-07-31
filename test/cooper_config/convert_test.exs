defmodule CooperConfig.ConvertTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest CooperConfig.Convert

  alias CooperConfig.Convert

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
      ip = %Cooper.IPv4{address: {127, 0, 0, 1}, prefix: nil}
      assert Convert.to_app_config(%{"my_app" => %{"ip" => ip}}) == [my_app: [ip: ip]]
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
end
