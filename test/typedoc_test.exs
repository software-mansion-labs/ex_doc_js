defmodule ExDocJs.TypedocTest do
  use ExUnit.Case, async: true

  alias ExDocJs.Typedoc

  defp fixture, do: File.read!(ExDocJs.BeamGenerator.fixture_path()) |> Jason.decode!()
  defp flat_fixture, do: File.read!(Path.expand("fixtures/flat.json", __DIR__)) |> Jason.decode!()
  defp rich_fixture, do: File.read!(Path.expand("fixtures/rich.json", __DIR__)) |> Jason.decode!()

  test "parses one module with two functions" do
    modules = Typedoc.parse(fixture())

    assert [%{path: ["Mylib", "MyLib", "JS", "Client"], doc: module_doc, functions: funcs}] =
             modules

    assert module_doc =~ "browser JS client"
    assert [create, connect] = funcs
    assert create.name == "create"
    assert connect.name == "connect"

    assert [%{comment: doc, parameters: [name, opts], return_type: "Client"}] =
             create.signatures

    assert doc =~ "Creates a client"
    assert name.name == "name"
    assert name.optional == false
    assert opts.optional == true

    assert [%{parameters: [], return_type: "void"}] = connect.signatures
  end

  test "root-level re-exports get a module name instead of an empty path" do
    # Default: derive the module from the project name ("my-sdk" -> ["My", "Sdk"]).
    assert [%{path: ["My", "Sdk"], functions: funcs}] = Typedoc.parse(flat_fixture())
    assert Enum.map(funcs, & &1.name) == ["parse", "stringify"]

    # Override: caller-supplied root module wins.
    assert [%{path: ["MyLib", "JS"]}] = Typedoc.parse(flat_fixture(), root_module: "MyLib.JS")
  end

  describe "rich TypeDoc output" do
    test "interfaces become types, and sources resolve against the entry point dir" do
      assert [%{path: ["Rich"], doc: module_doc, source: module_source, types: [opts]}] =
               Typedoc.parse(rich_fixture())

      assert module_doc == "The rich fixture."
      assert module_source == %{file: "src/index.ts", line: 1}

      assert opts.name == "Opts"
      assert opts.doc == "Options."
      assert opts.source == %{file: "src/client.ts", line: 4}

      assert [
               %{
                 name: "retries",
                 type: "number",
                 optional: true,
                 readonly: false,
                 doc: "How many retries."
               }
             ] = opts.properties

      assert opts.definition == "interface Opts {\n  retries?: number;\n}"
    end

    test "{@link} resolves to a reference, block tags and param docs survive" do
      assert [%{functions: [create, _pick]}] = Typedoc.parse(rich_fixture())
      assert create.async
      assert [signature] = create.signatures

      # Resolved link keeps its display text; an unresolved one degrades to code.
      assert signature.comment ==
               "Creates a client. See [`Opts`](`t:Rich.opts/0`) and `gone`."

      assert signature.block_tags == [{"@returns", "A client."}]
      assert [%{doc: "The name."}, %{doc: nil, default: "3"}] = signature.parameters
    end

    test "signature strings keep generics, type arguments and defaults" do
      assert [%{functions: [create, pick]}] = Typedoc.parse(rich_fixture())

      assert Typedoc.signature_string(hd(create.signatures), "create") ==
               "create(name: string, retries: number = 3): Promise<void>"

      assert Typedoc.signature_string(hd(create.signatures), "create", true) ==
               "async create(name: string, retries: number = 3): Promise<void>"

      assert Typedoc.heading_string(hd(create.signatures), "create") ==
               "create(name, retries = 3)"

      assert Typedoc.heading_string(hd(create.signatures), "create", true) ==
               "async create(name, retries = 3)"

      assert Typedoc.signature_string(hd(pick.signatures), "pick") ==
               "pick<T>(items: readonly T[], fn: (item: T) => boolean): T | null"
    end
  end
end
