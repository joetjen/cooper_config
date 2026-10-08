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

  describe "load!/2 option validation" do
    test "rejects an unknown option instead of silently dropping it" do
      # Both this library and Cooper ignore unknown keys on their own, so a
      # typo used to mean the option simply did not happen.
      error =
        assert_raise ArgumentError, fn ->
          CooperConfig.load!(@fixture, secret_modul: SomeModule)
        end

      assert Exception.message(error) =~ "unknown option(s): [:secret_modul]"
    end

    test "still accepts options forwarded to Cooper.load_file/2" do
      assert :ok = CooperConfig.load!(@fixture, cache: false, dotenv_override: true)
    end

    @tag :tmp_dir
    test "forwards :dotenv_dir, so .env files are read from where it says", %{tmp_dir: dir} do
      File.write!(Path.join(dir, ".env"), "COOPER_CONFIG_DIR_PROBE=from-dir\n")
      doc = Path.join(dir, "config.casc")

      File.write!(
        doc,
        "#@version = 1.0\ncooper_config_probe { v = ${COOPER_CONFIG_DIR_PROBE} }\n"
      )

      on_exit(fn -> Application.delete_env(:cooper_config_probe, :v) end)

      assert :ok = CooperConfig.load!(doc, cache: false, dotenv_dir: dir)
      assert Application.get_env(:cooper_config_probe, :v) == "from-dir"
    end

    test "forwards :modules to !module" do
      doc =
        Path.join(
          System.tmp_dir!(),
          "cooper_config_modules_#{System.unique_integer([:positive])}.casc"
        )

      File.write!(doc, "#@version = 1.0\ncooper_config_probe { m = !module(\"Crypto\") }\n")
      on_exit(fn -> Application.delete_env(:cooper_config_probe, :m) end)

      assert :ok = CooperConfig.load!(doc, cache: false, modules: %{"Crypto" => :crypto})
      assert Application.get_env(:cooper_config_probe, :m) == :crypto
    end
  end
end
