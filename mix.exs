defmodule ExDocJs.MixProject do
  use Mix.Project

  @source_url "https://github.com/example/ex_doc_js"

  def project do
    [
      app: :ex_doc_js,
      version: "0.1.0",
      description: "Generate TypeScript documentation inside ExDoc sites",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.2"},
      # Not `only: [:dev, :test]`: the plugin implements the ExDoc.Language
      # behaviour, so parent projects must compile ExDoc first.
      {:ex_doc, github: "software-mansion-labs/ex_doc", runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib priv/typedoc mix.exs README.md),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "ExDocJs",
      source_url: @source_url,
      source_url_pattern: &js_source_url/2
    ]
  end

  defp js_source_url(path, line) do
    "#{@source_url}/blob/main/src/js/#{path}#L#{line}"
  end
end
