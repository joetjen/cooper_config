defmodule CooperConfig.ProviderTest do
  use ExUnit.Case, async: true

  alias CooperConfig.Provider

  @fixture Path.join([__DIR__, "..", "fixtures", "config.casc"])
  @fixture_with_env Path.join([__DIR__, "..", "fixtures", "config_with_env.casc"])

  describe "init/1" do
    test "requires :path" do
      assert_raise KeyError, fn -> Provider.init([]) end
    end

    test "validates :path via Config.Provider.validate_config_path!/1" do
      assert_raise ArgumentError, fn -> Provider.init(path: :not_a_valid_path) end
    end

    test "accepts a literal string path" do
      assert %{path: @fixture} = Provider.init(path: @fixture)
    end

    test "defaults resolvers/tags/import_schemes to empty maps and reveal_secrets to true" do
      assert %{resolvers: %{}, tags: %{}, import_schemes: %{}, reveal_secrets: true} =
               Provider.init(path: @fixture)
    end
  end

  describe "load/2" do
    test "reads the CASC file and merges it into the app config, revealing secrets by default" do
      state = Provider.init(path: @fixture)

      assert Provider.load([], state) == [my_app: [password: "hunter2", port: 4000]]
    end

    test "deep-merges into config already present, same as Config.Reader.merge/2" do
      state = Provider.init(path: @fixture)

      assert Provider.load([my_app: [other: :untouched]], state) ==
               [my_app: [other: :untouched, password: "hunter2", port: 4000]]
    end

    test "reveal_secrets: false keeps the password wrapped" do
      state = Provider.init(path: @fixture, reveal_secrets: false)

      assert Provider.load([], state) ==
               [my_app: [password: %Cooper.Secret{value: "hunter2"}, port: 4000]]
    end

    test "passes :env through to Cooper.load_file/2" do
      state = Provider.init(path: @fixture_with_env, env: %{"APP_HOST" => "example.com"})

      assert Provider.load([], state) == [my_app: [host: "example.com"]]
    end

    test "raises with a formatted message when the file can't be loaded" do
      state = Provider.init(path: "/does/not/exist/nope.casc")

      assert_raise RuntimeError, ~r/failed to load CASC config/, fn ->
        Provider.load([], state)
      end
    end
  end
end
