defmodule Mix.Tasks.Cooper.LoadTest do
  use ExUnit.Case, async: false

  # Stands in for a consuming codebase's own secret type; `new/1` is the whole
  # contract `--secret-module` requires.
  defmodule OwnedSecret do
    @moduledoc false
    @enforce_keys [:value]
    defstruct [:value]

    def new(value), do: %__MODULE__{value: value}
  end

  # The task exists to fill the gap `Config.Provider` leaves under Mix: it
  # applies a document *before* whichever task starts applications, so a library
  # that validates its configuration at start still finds it there.

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "config/env"))

    File.write!(
      Path.join(dir, "config/config.casc"),
      ~s(#@version = 1.0\nimport "env/${MIX_ENV:dev}.casc"\n)
    )

    File.write!(
      Path.join(dir, "config/env/dev.casc"),
      "#@version = 1.0\nmix_load_demo { from = dev }\n"
    )

    File.write!(
      Path.join(dir, "config/env/test.casc"),
      ~s(#@version = 1.0\nmix_load_demo {\n from = test\n *token = "not-a-real-token"\n}\n)
    )

    on_exit(fn ->
      Application.delete_env(:mix_load_demo, :from)
      Application.delete_env(:mix_load_demo, :token)
    end)

    original = File.cwd!()
    File.cd!(dir)
    on_exit(fn -> File.cd!(original) end)

    :ok
  end

  test "loads the document for the current build environment" do
    # `MIX_ENV` is not an operating-system variable, so the task has to pass it
    # for the overlay import to resolve.
    Mix.Tasks.Cooper.Load.run([])

    assert Application.get_env(:mix_load_demo, :from) == :test
  end

  test "accepts an explicit path" do
    Mix.Tasks.Cooper.Load.run(["--path", "config/config.casc"])

    assert Application.get_env(:mix_load_demo, :from) == :test
  end

  test "reveals secrets by default" do
    Mix.Tasks.Cooper.Load.run([])

    assert Application.get_env(:mix_load_demo, :token) == "not-a-real-token"
  end

  test "wraps secrets when a module is named" do
    Mix.Tasks.Cooper.Load.run(["--secret-module", inspect(OwnedSecret)])

    assert %OwnedSecret{value: "not-a-real-token"} = Application.get_env(:mix_load_demo, :token)
  end

  test "a missing document fails loudly rather than leaving configuration absent" do
    File.rm!("config/config.casc")

    assert_raise RuntimeError, ~r/failed to load CASC config/, fn ->
      Mix.Tasks.Cooper.Load.run([])
    end
  end
end
