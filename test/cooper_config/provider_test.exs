defmodule CooperConfig.ProviderTest do
  use ExUnit.Case, async: true

  alias CooperConfig.Provider

  # Stands in for a consuming codebase's own secret type. See
  # `CooperConfig.ConvertTest` for why `:secret_module` exists at all.
  defmodule OwnedSecret do
    @moduledoc false
    @enforce_keys [:value]
    defstruct [:value]

    def new(value), do: %__MODULE__{value: value}
  end

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

    test "rejects an unknown option instead of ignoring it" do
      # The regression this prevents: passing `:secret_module` to a version that
      # predates it left secrets revealed in a release, with no warning anywhere.
      error =
        assert_raise ArgumentError, fn ->
          Provider.init(path: @fixture, secret_modul: OwnedSecret)
        end

      assert Exception.message(error) =~ "unknown option(s): [:secret_modul]"
      assert Exception.message(error) =~ "check the version you have installed"
    end

    test "accepts every documented option" do
      assert %{} =
               Provider.init(
                 path: @fixture,
                 env: %{},
                 resolvers: %{},
                 tags: %{},
                 import_schemes: %{},
                 dotenv: false,
                 dotenv_env: :prod,
                 dotenv_files: [],
                 reveal_secrets: false,
                 secret_module: OwnedSecret
               )
    end

    test "defaults secret_module to nil and captures it when given" do
      assert %{secret_module: nil} = Provider.init(path: @fixture)

      assert %{secret_module: OwnedSecret} =
               Provider.init(path: @fixture, secret_module: OwnedSecret)
    end

    test "defaults dotenv/dotenv_env/dotenv_files to nil (Cooper's own default applies)" do
      assert %{dotenv: nil, dotenv_env: nil, dotenv_files: nil} = Provider.init(path: @fixture)
    end

    test "captures dotenv/dotenv_env/dotenv_files when given" do
      state =
        Provider.init(
          path: @fixture,
          dotenv: false,
          dotenv_env: :prod,
          dotenv_files: ["/etc/my_app/.env"]
        )

      assert %{dotenv: false, dotenv_env: :prod, dotenv_files: ["/etc/my_app/.env"]} = state
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

    test "secret_module: re-wraps the password in the consumer's own type" do
      # The release path end to end: a provider state built from options that a
      # `mix release` writes into `sys.config`, loading a real file.
      state = Provider.init(path: @fixture, secret_module: OwnedSecret)

      assert Provider.load([], state) ==
               [my_app: [password: %OwnedSecret{value: "hunter2"}, port: 4000]]
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

    test "never populates Cooper's file cache" do
      absolute = Path.expand(@fixture)
      root = Path.dirname(absolute)
      Cooper.Cache.invalidate(absolute)

      state = Provider.init(path: @fixture)
      Provider.load([], state)

      # `Config.Provider` callbacks run before `:cooper`'s own OTP
      # application -- and `Cooper.Cache`'s GenServer/ETS table -- has
      # started, so `load/2` always forces `cache: false`; reaching for the
      # cache here would crash in a real release boot, not just be pointless.
      assert Cooper.Cache.fetch(absolute, root) == :miss
    end

    test "rejects :cache rather than accepting it and doing the opposite" do
      # It used to be ignored silently. Someone passing `cache: true` wants
      # caching, and getting none without being told is the same hazard as any
      # other silently dropped option.
      assert_raise ArgumentError, fn -> Provider.init(path: @fixture, cache: true) end
      assert_raise ArgumentError, fn -> Provider.init(path: @fixture, watch_env: true) end
    end
  end
end
