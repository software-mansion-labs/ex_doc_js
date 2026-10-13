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
  `:root_module` names the page ID for standalone exports and prefixes every
  class and namespace page ID. Displayed titles omit that prefix; the standalone
  exports page uses TypeDoc's library name. README content is omitted, and
  selected JavaScript modules and links use a theme-specific gold accent.
  """
  def configure(docs, options) when is_list(docs) and is_list(options) do
    entry_points = Keyword.fetch!(options, :entry_points)
    [_ | _] = entry_points

    docs =
      docs
      |> put_language()
      |> put_group(Keyword.get(options, :group, "JavaScript"))

    modules = ExDocJs.Generator.run(entry_points, options)
    put_style(docs, modules)
  end

  defp put_style(docs, modules) do
    pages =
      Enum.map(modules, fn module ->
        id = module |> Atom.to_string() |> String.trim_leading("Elixir.")
        "#{id}.html"
      end)

    page_links = Enum.map_join(pages, ", ", &~s|[href="#{&1}"]|)

    doc_links =
      Enum.map_join(modules, ", ", fn module ->
        id = module |> Atom.to_string() |> String.trim_leading("Elixir.")
        ~s|[href="#{id}.html"], [href^="#{id}.html#"]|
      end)

    style = """
    <style>
    body {
      --exdoc-js-accent: #f2d600;
      --exdoc-js-text: #9a8200;
    }
    body.dark {
      --exdoc-js-accent: #e2c45a;
      --exdoc-js-text: var(--exdoc-js-accent);
    }

    .sidebar .full-list > li:has(> a:is(#{page_links})) {
      --sidebarActiveItem: var(--exdoc-js-text);
      --sidebarLanguageAccentBar: var(--exdoc-js-accent);
      --main: var(--exdoc-js-accent);
    }
    .exdoc-js-page .content-inner {
      --textDetailAccent: var(--exdoc-js-accent);
    }
    .content-inner a:is(#{doc_links}),
    .exdoc-js-page .content-inner a[href^="#"] {
      --main: var(--exdoc-js-accent);
      --mainLight: var(--exdoc-js-accent);
      --link-color: var(--exdoc-js-text);
      --link-visited-color: var(--exdoc-js-text);
    }
    </style>
    <script>
    (() => {
      const pages = #{Jason.encode!(pages)};
      const update = () => {
        const page = decodeURIComponent(window.location.pathname.split("/").pop());
        document.documentElement.classList.toggle("exdoc-js-page", pages.includes(page));
      };
      update();
      window.addEventListener("exdoc:loaded", update);
    })();
    </script>
    """

    previous = Keyword.get(docs, :before_closing_head_tag, fn _ -> "" end)

    Keyword.put(docs, :before_closing_head_tag, fn format ->
      previous.(format) <> if(format == :html and modules != [], do: style, else: "")
    end)
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
