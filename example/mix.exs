defmodule Example.MixProject do
  use Mix.Project

  @source_url "https://github.com/example/ex_doc_js"

  def project do
    [
      app: :example,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: fn -> docs() end
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_doc, path: "../../ex_doc", override: true},
      {:ex_doc_js, path: ".."}
    ]
  end

  defp docs do
    [
      main: "ExampleApp.Server",
      source_url: @source_url,
      groups_for_modules: [
        "Elixir": fn _ -> true end
      ],
      source_url_pattern: &source_url/2
    ]
    |> ExDocJs.configure(
      entry_points: ["src/index.ts"],
      root_module: "ExampleLib",
      tsconfig: "tsconfig.json"
    )
  end

  defp source_url(path, line), do: "#{@source_url}/blob/main/example/#{path}#L#{line}"
end
