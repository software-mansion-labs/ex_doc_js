defmodule ExDocJs.ExDoc.TypeScriptTest do
  use ExUnit.Case, async: true

  alias ExDocJs.ExDoc.TypeScript

  defp chunk(metadata, entries \\ []) do
    {:docs_v1, 7, :typescript, "text/markdown", :none, metadata, entries}
  end

  describe "module_data/3" do
    test "takes its source location from the module metadata" do
      data = TypeScript.module_data(MyLib.Client, chunk(%{source_file: "src/client.ts"}), %{})

      assert data.id == "MyLib.Client"
      assert data.source_file == "src/client.ts"
      assert data.source_line == 7
      assert data.default_groups == ["Types", "Properties", "Functions"]
    end

    # TypeDoc run with --excludeSources emits no locations at all, and ExDoc has
    # no nil handling for a module's source path.
    test "falls back to a stand-in path when the chunk carries no source" do
      data = TypeScript.module_data(MyLib.Client, chunk(%{language: :typescript}), %{})

      assert data.source_file == "MyLib.Client.ts"
    end
  end

  describe "doc_data/2" do
    test "types are addressable under a t: prefix, functions carry annotations" do
      type =
        {{:type, :opts, 0}, 4, ["Opts"], :none,
         %{source_file: "src/client.ts", specs: ["interface Opts {\n}"]}}

      assert %{id_key: "t:", default_group: "Types", type: :type, specs: ["interface Opts {\n}"]} =
               TypeScript.doc_data(type, %{})

      rest =
        {{:function, :sum, 1}, 9, ["sum(...n)"], :none,
         %{variadic: true, specs: ["sum(...n: number[]): number"]}}

      assert %{
               extra_annotations: ["variadic"],
               source_file: nil,
               source_line: 9,
               specs: ["sum(...n: number[]): number"]
             } =
               TypeScript.doc_data(rest, %{})
    end

    test "formats specs" do
      spec = "compactMap<T, U>(items: readonly T[], fn: (item: T) => U): U[]"

      assert TypeScript.autolink_spec(spec, %{}) ==
               "compactMap&lt;T, U&gt;(items: readonly T[], fn: (item: T) =&gt; U): U[]"

      assert TypeScript.format_spec(spec) == spec
      assert TypeScript.format_spec_attribute(%{type: :function}) == "@spec"
      assert TypeScript.format_spec_attribute(%{type: :property}) == "@spec"
      assert TypeScript.format_spec_attribute(%{type: :type}) == "@type"
    end
  end
end
