defmodule ExDocJsTest do
  use ExUnit.Case

  test "generates inputs and preserves existing docs options" do
    docs = [
      extras: ["README.md"],
      formatters: ["html"],
      languages: %{custom: CustomLanguage},
      groups_for_modules: [
        JavaScript: ~r/^Existing/,
        Internal: fn _ -> false end
      ]
    ]

    configured =
      ExDocJs.configure(docs,
        entry_points: ["example/src/index.ts"],
        root_module: "ConfiguredSdk",
        tsconfig: "example/tsconfig.json"
      )

    assert configured[:extras] == ["README.md"]
    assert configured[:formatters] == ["html"]

    assert configured[:languages] == %{
             custom: CustomLanguage,
             typescript: ExDocJs.ExDoc.TypeScript
           }

    assert [{:JavaScript, [javascript?, existing_pattern]}, {:Internal, internal?}] =
             configured[:groups_for_modules]

    assert javascript?.(%{language: :typescript})
    assert Regex.source(existing_pattern) == "^Existing"
    refute internal?.(%{})
    assert File.regular?(Path.join(Mix.Project.compile_path(), "Elixir.ConfiguredSdk.beam"))
  end

  test "rejects a TypeScript language conflict" do
    assert_raise ArgumentError, ~r/TypeScript is already registered/, fn ->
      ExDocJs.configure([languages: %{typescript: OtherLanguage}],
        entry_points: ["example/src/index.ts"]
      )
    end
  end

  test "removes beams from the previous generation" do
    ExDocJs.configure([],
      entry_points: ["example/src/index.ts"],
      root_module: "PreviousSdk",
      tsconfig: "example/tsconfig.json"
    )

    previous = Path.join(Mix.Project.compile_path(), "Elixir.PreviousSdk.beam")
    assert File.regular?(previous)

    ExDocJs.configure([],
      entry_points: ["example/src/index.ts"],
      root_module: "CurrentSdk",
      tsconfig: "example/tsconfig.json"
    )

    refute File.exists?(previous)
    assert File.regular?(Path.join(Mix.Project.compile_path(), "Elixir.CurrentSdk.beam"))
  end

  test "reports missing Node.js" do
    path = System.get_env("PATH")
    System.put_env("PATH", "")
    on_exit(fn -> System.put_env("PATH", path) end)

    assert_raise RuntimeError, "Node.js is required to generate TypeScript documentation", fn ->
      ExDocJs.TypeDocRunner.run(["example/src/index.ts"], "ignored.json", [])
    end
  end
end
