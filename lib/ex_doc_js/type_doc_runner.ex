defmodule ExDocJs.TypeDocRunner do
  @moduledoc false

  def run(entry_points, output, options) do
    node =
      System.find_executable("node") ||
        raise "Node.js is required to generate TypeScript documentation"

    request = %{
      entryPoints: entry_points,
      name: Keyword.get(options, :root_module),
      output: output,
      tsconfig: Keyword.get(options, :tsconfig)
    }

    request_path = Path.join(Path.dirname(output), "typedoc-request.json")
    File.write!(request_path, Jason.encode!(request))

    script = Path.join([priv_dir(), "typedoc", "run.mjs"])

    case System.cmd(node, [script, request_path], cd: File.cwd!(), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {message, status} -> raise "TypeDoc failed with status #{status}:\n#{String.trim(message)}"
    end
  end

  defp priv_dir do
    :ex_doc_js
    |> :code.priv_dir()
    |> to_string()
  end
end
