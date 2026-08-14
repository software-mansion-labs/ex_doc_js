defmodule Mix.Tasks.ExDocJs.Vendor do
  use Mix.Task

  @shortdoc "Builds the bundled TypeDoc runtime for release"

  @impl true
  def run([]) do
    root = Path.expand("../../..", __DIR__)
    runtime = Path.join(root, "vendor/typedoc")
    target = Path.join(root, "priv/typedoc")
    npm = System.find_executable("npm") || Mix.raise("npm is required to vendor TypeDoc")

    {_, 0} = System.cmd(npm, ["ci", "--omit=dev"], cd: runtime, into: IO.stream())

    File.mkdir_p!(target)
    File.cp!(Path.join(runtime, "run.mjs"), Path.join(target, "run.mjs"))
    File.rm_rf!(Path.join(target, "node_modules"))
    File.cp_r!(Path.join(runtime, "node_modules"), Path.join(target, "node_modules"))

    Mix.shell().info("TypeDoc runtime written to #{Path.relative_to_cwd(target)}")
  end
end
