defmodule ExDocJs.SpecLinksTest do
  use ExUnit.Case

  @tag :tmp_dir
  test "links type identities through generated docs", %{tmp_dir: tmp_dir} do
    entry = Path.join(tmp_dir, "index.ts")
    tsconfig = Path.join(tmp_dir, "tsconfig.json")
    json = Path.join(tmp_dir, "typedoc.json")
    ebin = Path.join(tmp_dir, "ebin")
    output = Path.join(tmp_dir, "doc")
    File.mkdir_p!(ebin)
    on_exit(fn -> Code.delete_path(ebin) end)

    File.write!(entry, """
    export namespace Left { export type Shared = { left: string }; }
    export namespace Right { export type Shared = { right: number }; }
    export interface Options {
      nested?: Left.Shared[];
      callback: (value: Right.Shared) => Left.Shared;
      label: "<tag>";
    }
    export type Envelope<T> = { value: T; options: Options };
    export function choose(input: Left.Shared): Right.Shared { return { right: 1 }; }
    export function wrap<Options>(input: Options): Promise<Envelope<Options>> { throw 0; }
    export class Client { readonly options!: Options; }
    export function client(): Client { return new Client(); }
    """)

    File.write!(tsconfig, ~s|{"files": ["index.ts"]}|)
    ExDocJs.TypeDocRunner.run([entry], json, tsconfig: tsconfig)
    ExDocJs.BeamGenerator.run(ebin, json, root_module: "LinksSDK")

    start_supervised!(ExDoc.Refs)

    results =
      ExDoc.generate("Links", "0.1.0", [ebin],
        output: output,
        formatters: ["html", "markdown"],
        languages: %{typescript: ExDocJs.ExDoc.TypeScript}
      )

    assert Enum.all?(results, &(!&1.warned?))
    html = File.read!(Path.join(output, "LinksSDK.html"))
    client = File.read!(Path.join(output, "LinksSDK.Client.html"))
    markdown = File.read!(Path.join(output, "LinksSDK.md"))

    assert html =~
             ~s|choose(input: <a href="LinksSDK.Left.html#t:shared/0">Shared</a>): <a href="LinksSDK.Right.html#t:shared/0">Shared</a>|

    assert html =~
             ~s|async wrap&lt;Options&gt;(input: Options): Promise&lt;<a href="#t:envelope/0">Envelope</a>&lt;Options&gt;&gt;|

    assert html =~ ~s|nested?: <a href="LinksSDK.Left.html#t:shared/0">Shared</a>[]|

    assert html =~
             ~s|callback: (value: <a href="LinksSDK.Right.html#t:shared/0">Shared</a>) =&gt; <a href="LinksSDK.Left.html#t:shared/0">Shared</a>|

    assert html =~ ~s|label: &quot;&lt;tag&gt;&quot;|
    assert html =~ ~s|client(): <a href="LinksSDK.Client.html">Client</a>|
    assert client =~ ~s|readonly options: <a href="LinksSDK.html#t:options/0">Options</a>|
    assert markdown =~ "wrap<Options>(input: Options): Promise<Envelope<Options>>"
    refute markdown =~ "<a href="
  end
end
