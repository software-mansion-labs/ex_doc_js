defmodule ExDocJs.BeamGeneratorTest do
  use ExUnit.Case

  alias ExDocJs.BeamGenerator

  @tag :tmp_dir
  test "namespaces API owners", %{tmp_dir: tmp_dir} do
    entry = Path.join(tmp_dir, "index.ts")
    tsconfig = Path.join(tmp_dir, "tsconfig.json")
    json = Path.join(tmp_dir, "typedoc.json")
    ebin = Path.join(tmp_dir, "ebin")
    File.mkdir_p!(ebin)
    on_exit(fn -> Code.delete_path(ebin) end)

    File.write!(entry, """
    /** See {@link OwnershipServer.call}. */
    export function helper(): void {}

    export class OwnershipClient {
      readonly genserver!: OwnershipServer;
      readonly shared?: SharedAPI;
      send(): void {}
    }

    export class OtherClient {
      readonly shared!: SharedAPI;
    }

    export type OwnershipServer = {
      call(): void;
      cast(): void;
    };

    export type SharedAPI = { inspect(): void };
    """)

    File.write!(tsconfig, ~s({"files": ["index.ts"]}))
    ExDocJs.TypeDocRunner.run([entry], json, tsconfig: tsconfig)

    modules = BeamGenerator.run(ebin, json, root_module: "OwnershipSDK")

    assert Enum.sort(modules) == [
             OwnershipSDK,
             OwnershipSDK.OtherClient,
             OwnershipSDK.OwnershipClient,
             OwnershipSDK.OwnershipClient.Genserver,
             OwnershipSDK.SharedAPI
           ]

    for {module, functions} <- [
          {OwnershipSDK, [:helper]},
          {OwnershipSDK.OwnershipClient, [:genserver, :shared, :OwnershipClient, :send]},
          {OwnershipSDK.OwnershipClient.Genserver, [:call, :cast]},
          {OwnershipSDK.OtherClient, [:shared, :OtherClient]},
          {OwnershipSDK.SharedAPI, [:inspect]}
        ] do
      {:docs_v1, _, :typescript, _, _, _, entries} = Code.fetch_docs(module)
      assert for({{:function, name, _}, _, _, _, _} <- entries, do: name) == functions
    end

    {:docs_v1, _, _, _, :none, _, [genserver, shared | _]} =
      Code.fetch_docs(OwnershipSDK.OwnershipClient)

    assert {{:function, :genserver, 0}, _, ["genserver"], %{"en" => property_doc},
            %{kind: :property, specs: ["readonly genserver: OwnershipServer"]}} = genserver

    assert {{:function, :shared, 0}, _, ["shared"], _,
            %{kind: :property, specs: ["readonly shared?: SharedAPI"]}} = shared

    assert property_doc ==
             "[`OwnershipSDK.OwnershipClient.Genserver`](`OwnershipSDK.OwnershipClient.Genserver`)"

    start_supervised!(ExDoc.Refs)
    config = ExDoc.Config.build(languages: %{typescript: ExDocJs.ExDoc.TypeScript})
    {nodes, []} = ExDoc.Retriever.docs_from_dir([ebin], config)
    client = Enum.find(nodes, &(&1.module == OwnershipSDK.OwnershipClient))

    assert [%{title: "Properties", docs: [property, _]}, %{title: "Functions"}] =
             client.docs_groups

    assert %{
             type: :property,
             signature: "genserver",
             id: "genserver/0",
             source_specs: ["readonly genserver: OwnershipServer"]
           } = property

    {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(OwnershipSDK)

    assert [{_, _, _, %{"en" => helper_doc}, _}] =
             for({{:function, _, _}, _, _, _, _} = entry <- entries, do: entry)

    assert helper_doc ==
             "See [`OwnershipServer.call`](`OwnershipSDK.OwnershipClient.Genserver.call/0`)."
  end

  @tag :tmp_dir
  test "documents exported aliases", %{tmp_dir: tmp_dir} do
    entry = Path.join(tmp_dir, "index.ts")
    tsconfig = Path.join(tmp_dir, "tsconfig.json")
    json = Path.join(tmp_dir, "typedoc.json")
    ebin = Path.join(tmp_dir, "ebin")
    File.mkdir_p!(ebin)
    on_exit(fn -> Code.delete_path(ebin) end)

    File.write!(entry, """
    /** Dimensions. See {@link Result}. */
    export type Size = {
      /** Column count. */
      readonly columns: number;
      rows?: number;
    };
    export type Result<T extends string = "ok"> =
      { ok: true; data: T } | { ok: false; error: string };
    export type Errors = { "vm:exit": { reason: string } };
    export type Serialized<K extends keyof Errors = keyof Errors> = {
      [P in K]: { tag: P; data: Errors[P] }
    }[K];
    export type AnyValue = unknown;
    export type Event = Result;
    export type Callback = (input: string) => number;
    """)

    File.write!(tsconfig, ~s({"files": ["index.ts"]}))
    ExDocJs.TypeDocRunner.run([entry], json, tsconfig: tsconfig)
    assert BeamGenerator.run(ebin, json, root_module: "AliasSDK") == [AliasSDK]

    {:docs_v1, _, :typescript, _, _, _, entries} = Code.fetch_docs(AliasSDK)

    definitions =
      Map.new(entries, fn {{:type, name, 0}, _, _, _, %{specs: [definition]}} ->
        {name, definition}
      end)

    assert definitions == %{
             any_value: "type AnyValue = unknown",
             callback: "type Callback = (input: string) => number",
             errors: "type Errors = {\n  \"vm:exit\": {\n    reason: string;\n  };\n}",
             event: "type Event = Result",
             result:
               "type Result<T extends string = \"ok\"> = {\n  data: T;\n  ok: true;\n} | {\n  error: string;\n  ok: false;\n}",
             serialized:
               "type Serialized<K extends keyof Errors = keyof Errors> = {\n  [P in K]: {\n    data: Errors[P];\n    tag: P;\n  };\n}[K]",
             size: "type Size = {\n  readonly columns: number;\n  rows?: number;\n}"
           }

    {{:type, :size, 0}, 2, ["Size"], %{"en" => doc}, %{source_file: source}} =
      Enum.find(entries, fn {{:type, name, 0}, _, _, _, _} -> name == :size end)

    assert String.ends_with?(source, "index.ts")

    assert doc ==
             "Dimensions. See [`Result`](`t:AliasSDK.result/0`).\n\n## Properties\n\n  * `columns: number` - Column count."
  end

  test "writes a loadable beam with a :typescript docs chunk" do
    ebin = Path.join(System.tmp_dir!(), "ex_doc_js_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(ebin)

    try do
      assert BeamGenerator.run(ebin, BeamGenerator.fixture_path()) == [Mylib.MyLib.JS.Client]
      Code.prepend_path(ebin)

      {:docs_v1, _, :typescript, _, module_doc, %{language: :typescript}, entries} =
        Code.fetch_docs(Mylib.MyLib.JS.Client)

      assert module_doc == %{"en" => "The browser JS client.\n\nLink to the Elixir side."}

      assert [
               {{:function, :create, 2}, 1, ["create(name, opts?)"], %{"en" => _},
                %{defaults: 1, specs: ["create(name: string, opts?: Opts): Client"]}},
               {{:function, :connect, 0}, 1, ["connect()"], %{"en" => _},
                %{specs: ["connect(): void"]}}
             ] = entries
    after
      File.rm_rf!(ebin)
    end
  end

  test "flat root re-exports produce a named module" do
    ebin = Path.join(System.tmp_dir!(), "ex_doc_js_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(ebin)
    flat = Path.expand("fixtures/flat.json", __DIR__)

    try do
      assert BeamGenerator.run(ebin, flat) == [:"Elixir.My.Sdk"]
      Code.prepend_path(ebin)

      {:docs_v1, _, :typescript, _, _, _, entries} = Code.fetch_docs(:"Elixir.My.Sdk")

      assert [
               {{:function, :parse, 2}, 1, ["parse(input, opts?)"], _,
                %{defaults: 1, specs: ["parse(input: string, opts?: Opts): Node"]}},
               {{:function, :stringify, 1}, 1, ["stringify(node)"], _,
                %{specs: ["stringify(node: Node): string"]}}
             ] = entries
    after
      File.rm_rf!(ebin)
    end
  end

  test "types come first and entries carry their own source location" do
    ebin = Path.join(System.tmp_dir!(), "ex_doc_js_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(ebin)
    rich = Path.expand("fixtures/rich.json", __DIR__)

    try do
      assert BeamGenerator.run(ebin, rich) == [:"Elixir.Rich"]
      Code.prepend_path(ebin)

      {:docs_v1, 1, :typescript, _, _, %{source_file: "src/index.ts"}, entries} =
        Code.fetch_docs(:"Elixir.Rich")

      assert [
               {{:type, :opts, 0}, 4, ["Opts"], %{"en" => opts_doc},
                %{
                  source_file: "src/client.ts",
                  specs: ["interface Opts {\n  retries?: number;\n}"]
                }},
               {{:function, :create, 2}, 12, ["async create(name, retries = 3)"],
                %{"en" => create_doc},
                %{
                  defaults: 1,
                  source_file: "src/client.ts",
                  specs: ["async create(name: string, retries: number = 3): Promise<void>"]
                }},
               {{:function, :pick, 2}, 5, _, _, %{source_file: "src/utils.ts"}}
             ] = entries

      assert opts_doc == "Options.\n\n## Properties\n\n  * `retries?: number` - How many retries."

      assert create_doc =~ "## Parameters\n\n  * `name` - The name."
      assert create_doc =~ "## Returns\n\nA client."
    after
      File.rm_rf!(ebin)
    end
  end

  test ":root_module overrides the derived name" do
    ebin = Path.join(System.tmp_dir!(), "ex_doc_js_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(ebin)
    flat = Path.expand("fixtures/flat.json", __DIR__)

    try do
      assert BeamGenerator.run(ebin, flat, root_module: "MyLib.JS") == [:"Elixir.MyLib.JS"]
    after
      File.rm_rf!(ebin)
    end
  end
end
