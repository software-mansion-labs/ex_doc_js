defmodule ExDocJs.BeamGenerator do
  @moduledoc false

  alias ExDocJs.Typedoc

  @doc """
  Reads TypeDoc `out.json` and writes one fake `.beam` per module into `ebin_dir`,
  each carrying an EEP-48 Docs chunk whose language is `:typescript`.

  Returns the list of written module atoms. Adds `ebin_dir` to the code path.

  Options are passed to `ExDocJs.Typedoc.parse/2`; notably `:root_module` names
  the module that root-level re-exports land in.
  """
  def run(ebin_dir, json_path, opts \\ []) do
    decoded = json_path |> File.read!() |> Jason.decode!()

    modules = Typedoc.parse(decoded, opts)

    wrote =
      Enum.map(modules, fn module ->
        beam = build_beam(module)
        File.write!(Path.join(ebin_dir, "#{atom_string(module)}.beam"), beam)
        module_atom(module)
      end)

    Code.prepend_path(ebin_dir)
    wrote
  end

  defp build_beam(module) do
    mod = module_atom(module)
    docs = docs_v1(module)

    {:ok, ^mod, binary, _warnings} =
      :compile.forms(
        [{:attribute, 1, :module, mod}],
        [:return, {:extra_chunks, [{"Docs", :erlang.term_to_binary(docs)}]}]
      )

    binary
  end

  defp docs_v1(module) do
    entries =
      Enum.map(module.types, &type_entry/1) ++
        Enum.map(module.properties, &property_entry/1) ++
        Enum.map(module.functions, &function_entry/1)

    metadata = put_source(%{language: :typescript}, module.source)

    {:docs_v1, line(module.source), :typescript, "text/markdown", or_none(module.doc), metadata,
     entries}
  end

  defp function_entry(function) do
    arity = Typedoc.arity(function)
    min_required = function.signatures |> Enum.map(&required_count/1) |> Enum.min()
    widest = Enum.find(function.signatures, &(length(&1.parameters) == arity))

    metadata =
      %{}
      |> Map.put(
        :specs,
        Enum.map(
          function.signatures,
          &Typedoc.signature_string(&1, function.name, function.async)
        )
      )
      |> put_defaults(arity - min_required)
      |> put_variadic(variadic?(function))
      |> put_source(function.source)

    signature = Typedoc.heading_string(widest, function.name, function.async)

    {{:function, String.to_atom(function.name), arity}, line(function.source), [signature],
     or_none(function_doc(function)), metadata}
  end

  defp type_entry(type) do
    {{:type, String.to_atom(Typedoc.type_name(type.name)), 0}, line(type.source), [type.name],
     or_none(type_doc(type)), put_source(%{specs: [type.definition]}, type.source)}
  end

  defp property_entry(property) do
    # EEP-48 has no property kind; the language adapter reads it from metadata.
    metadata = put_source(%{kind: :property, specs: [property.definition]}, property.source)

    {{:function, String.to_atom(property.name), 0}, line(property.source), [property.name],
     or_none(property.doc), metadata}
  end

  # A type renders as its description followed by its members: ExDoc has
  # nowhere structural to put TS property declarations.
  defp type_doc(type) do
    sections([type.doc, list_section("Properties", type.properties, &property_item/1)])
  end

  defp property_item(property) do
    name = if property.optional, do: property.name <> "?", else: property.name
    item("`#{name}: #{property.type}`", property.doc)
  end

  defp function_doc(function) do
    [widest | _] = Enum.sort_by(function.signatures, &length(&1.parameters), :desc)

    sections([
      function.signatures |> Enum.map_join("\n\n", &(&1.comment || "")) |> trim_or_nil(),
      list_section("Parameters", widest.parameters, &parameter_item/1),
      block_tags(widest)
    ])
  end

  defp parameter_item(parameter), do: item("`#{parameter.name}`", parameter.doc)

  defp block_tags(signature) do
    signature.block_tags
    |> Enum.reject(fn {_tag, content} -> is_nil(content) end)
    |> Enum.map_join("\n\n", fn {tag, content} -> "## #{tag_title(tag)}\n\n#{content}" end)
    |> trim_or_nil()
  end

  defp tag_title("@" <> tag), do: String.capitalize(tag)
  defp tag_title(tag), do: tag

  defp list_section(title, items, render) do
    case Enum.filter(items, & &1.doc) do
      [] -> nil
      documented -> "## #{title}\n\n" <> Enum.map_join(documented, "\n", render)
    end
  end

  defp item(term, doc), do: "  * #{term} - #{doc}"

  defp sections(parts) do
    parts |> Enum.reject(&is_nil/1) |> Enum.join("\n\n") |> trim_or_nil()
  end

  defp trim_or_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp required_count(signature) do
    signature.parameters
    |> Enum.reject(&(Typedoc.optional_parameter?(&1) or &1.rest))
    |> length()
  end

  defp variadic?(function) do
    Enum.any?(function.signatures, fn signature ->
      Enum.any?(signature.parameters, & &1.rest)
    end)
  end

  defp put_defaults(metadata, 0), do: metadata
  defp put_defaults(metadata, defaults), do: Map.put(metadata, :defaults, defaults)

  defp put_variadic(metadata, false), do: metadata
  defp put_variadic(metadata, true), do: Map.put(metadata, :variadic, true)

  defp put_source(metadata, nil), do: metadata
  defp put_source(metadata, source), do: Map.put(metadata, :source_file, source.file)

  defp line(nil), do: 1
  defp line(source), do: source.line

  defp module_atom(module), do: String.to_atom(atom_string(module))

  defp atom_string(%{path: []} = module),
    do: raise(ArgumentError, "module with empty path: #{inspect(module)}")

  defp atom_string(module), do: "Elixir." <> Enum.join(module.path, ".")

  defp or_none(nil), do: :none
  defp or_none(""), do: :none
  defp or_none(text), do: %{"en" => text}

  def fixture_path, do: Path.expand("../../test/fixtures/out.json", __DIR__)
end
