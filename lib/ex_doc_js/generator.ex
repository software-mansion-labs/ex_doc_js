defmodule ExDocJs.Generator do
  @moduledoc false

  alias ExDocJs.{BeamGenerator, TypeDocRunner}

  def run(entry_points, options) do
    build_dir = Path.join(Mix.Project.build_path(), "ex_doc_js")
    json_path = Path.join(build_dir, "typedoc.json")
    manifest_path = Path.join(build_dir, "beams")
    ebin_dir = Mix.Project.compile_path()

    File.mkdir_p!(build_dir)
    File.mkdir_p!(ebin_dir)
    TypeDocRunner.run(entry_points, json_path, options)
    cleanup(manifest_path, ebin_dir)

    generator_options = Keyword.take(options, [:root_module])
    modules = BeamGenerator.run(ebin_dir, json_path, generator_options)
    write_manifest(manifest_path, modules)
    modules
  end

  defp cleanup(manifest_path, ebin_dir) do
    if File.regular?(manifest_path) do
      manifest_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.each(fn filename ->
        basename = Path.basename(filename)
        ^basename = filename
        File.rm(Path.join(ebin_dir, filename))
      end)
    end
  end

  defp write_manifest(manifest_path, modules) do
    content = Enum.map_join(modules, "\n", &(Atom.to_string(&1) <> ".beam"))
    File.write!(manifest_path, content <> "\n")
  end
end
