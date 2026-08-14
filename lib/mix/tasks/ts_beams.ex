defmodule Mix.Tasks.TsBeams do
  @shortdoc "Write fake .beam files (TypeDoc JSON) into the compile path"

  use Mix.Task

  @requirements ["compile"]

  @moduledoc """
  Reads the TypeDoc `out.json` fixture and writes one fake `.beam` per module
  into the project's compile path, each carrying an EEP-48 Docs chunk with
  language `:typescript`.

  Writing into the compile path is what makes the standard `mix docs` task treat
  the generated modules as source beams. `mix docs` is aliased to run this task
  beforehand.

  ## Usage

      mix ts_beams [PATH] [--root-module MODULE]

  `PATH` is the TypeDoc JSON (defaults to the bundled fixture). `--root-module`
  names the module that root-level re-exports land in; without it the module is
  derived from the TypeDoc project name.
  """

  @impl true
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [root_module: :string])

    json_path =
      case rest do
        [path | _] -> path
        [] -> ExDocJs.BeamGenerator.fixture_path()
      end

    generate(json_path, opts)
  end

  defp generate(json_path, opts) do
    ebin = Mix.Project.compile_path()
    File.mkdir_p!(ebin)

    written = ExDocJs.BeamGenerator.run(ebin, json_path, opts)

    Mix.shell().info("Wrote #{length(written)} TS docs module(s) from #{json_path}:")

    for module <- written do
      {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(module)

      arities =
        Enum.map_join(entries, ", ", fn {{_, name, arity}, _, _, _, _} -> "#{name}/#{arity}" end)

      id = module |> Atom.to_string() |> String.trim_leading("Elixir.")
      Mix.shell().info("  #{id}: #{arities}")
    end
  end
end
