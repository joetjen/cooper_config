defmodule CooperConfigTest do
  use ExUnit.Case, async: false

  @fixture Path.join([__DIR__, "fixtures", "config.casc"])
  @fixture_with_env Path.join([__DIR__, "fixtures", "config_with_env.casc"])

  setup do
    on_exit(fn ->
      Enum.each([:port, :password, :host, :other], &Application.delete_env(:my_app, &1))
    end)
  end

  describe "load!/2" do
    test "reads the CASC file and merges it into Application config, revealing secrets by default" do
      assert CooperConfig.load!(@fixture) == :ok
      assert Application.get_env(:my_app, :port) == 4000
      assert Application.get_env(:my_app, :password) == "hunter2"
    end

    test "reveal_secrets: false keeps the password wrapped" do
      assert CooperConfig.load!(@fixture, reveal_secrets: false) == :ok
      assert Application.get_env(:my_app, :password) == %Cooper.Secret{value: "hunter2"}
    end

    test "overwrites existing keys but leaves others untouched" do
      Application.put_env(:my_app, :other, :untouched)
      Application.put_env(:my_app, :port, :stale)

      assert CooperConfig.load!(@fixture) == :ok
      assert Application.get_env(:my_app, :other) == :untouched
      assert Application.get_env(:my_app, :port) == 4000
    end

    test "passes options through to Cooper.load_file/2" do
      assert CooperConfig.load!(@fixture_with_env, env: %{"APP_HOST" => "example.com"}) == :ok
      assert Application.get_env(:my_app, :host) == "example.com"
    end

    test "raises with a formatted message when the file can't be loaded" do
      assert_raise RuntimeError, ~r/failed to load CASC config/, fn ->
        CooperConfig.load!("/does/not/exist/nope.casc")
      end
    end

    test "uses Cooper's cache, unlike CooperConfig.Provider" do
      absolute = Path.expand(@fixture)
      root = Path.dirname(absolute)
      Cooper.Cache.invalidate(absolute)

      assert CooperConfig.load!(@fixture) == :ok
      assert {:ok, _tree, _vars, _guard_names} = Cooper.Cache.fetch(absolute, root)
    end
  end
end
