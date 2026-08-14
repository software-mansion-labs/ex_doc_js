defmodule ExDocJs do
  @moduledoc """
  Adds TypeScript modules to an ExDoc build.

  Call `configure/2` from a lazy `:docs` function in `mix.exs`:

      docs: fn ->
        [main: "MyApp", extras: ["README.md"]]
        |> ExDocJs.configure(entry_points: ["assets/js/index.ts"])
      end
  """

  @doc """
  Generates TypeScript documentation inputs and adds the TypeScript language
  adapter to existing ExDoc options.

  `:entry_points` is required. `:root_module`, `:tsconfig`, and `:group` are
  optional. Set `:group` to `false` to keep ExDoc's existing module grouping.
  `:root_module` names the page for standalone exports and prefixes every
  class and namespace page.
  """
  def configure(docs, options) when is_list(docs) and is_list(options) do
    entry_points = Keyword.fetch!(options, :entry_points)
    [_ | _] = entry_points

    docs =
      docs
      |> put_language()
      |> put_group(Keyword.get(options, :group, "JavaScript"))

    ExDocJs.Generator.run(entry_points, options)
    docs
  end

  defp put_language(docs) do
    languages = Keyword.get(docs, :languages, %{})

    case languages do
      %{typescript: ExDocJs.ExDoc.TypeScript} ->
        docs

      %{typescript: other} ->
        raise ArgumentError,
              "TypeScript is already registered to #{inspect(other)} in ExDoc :languages"

      %{} ->
        Keyword.put(docs, :languages, Map.put(languages, :typescript, ExDocJs.ExDoc.TypeScript))
    end
  end

  defp put_group(docs, false), do: docs

  defp put_group(docs, group) when is_binary(group) do
    groups = Keyword.get(docs, :groups_for_modules, [])
    matcher = fn metadata -> metadata[:language] == :typescript end

    groups =
      if Enum.any?(groups, fn {name, _patterns} -> to_string(name) == group end) do
        Enum.map(groups, fn {name, patterns} = entry ->
          if to_string(name) == group do
            {name, [matcher | List.wrap(patterns)]}
          else
            entry
          end
        end)
      else
        [{group, matcher} | groups]
      end

    Keyword.put(docs, :groups_for_modules, groups)
  end
end
