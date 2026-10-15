defmodule ExDocJs.Typedoc do
  @moduledoc false

  alias ExDocJs.Spec

  @type_alias_kind 2_097_152
  # Containers own callable members; interfaces and aliases also get type entries.
  @container_kinds [2, 4, 8, 128, @type_alias_kind]
  @interface_kind 256

  @doc """
  Parses a decoded TypeDoc JSON tree into module structs.

  Comments are resolved in a second pass, once every function and type is known,
  so that TSDoc `{@link}` tags can be turned into ExDoc references.
  """
  def parse(decoded, opts \\ []) do
    root = opts |> Keyword.get(:root_module) |> root_segments(decoded)
    context = context(decoded)

    modules = decoded |> build(root, context) |> place_property_apis()

    modules =
      Enum.map(modules, fn module ->
        title =
          case Enum.drop(module.path, length(root)) do
            [] -> Map.fetch!(decoded, "name")
            path -> Enum.join(path, ".")
          end

        Map.put(module, :title, title)
      end)

    index = index(modules)
    module_index = Map.new(modules, &{&1.id, {Enum.join(&1.path, "."), &1.title}})

    Enum.map(modules, &render(&1, index, module_index))
  end

  # TypeDoc reports `sources[].fileName` relative to its base path, which is the
  # common directory of the entry points. `files.entries` holds those entry
  # points relative to the project root, which is what source links need.
  defp context(decoded) do
    entries = decoded |> Map.get("files", %{}) |> Map.get("entries", %{}) |> Map.values()

    base_dir =
      case entries do
        [] -> ""
        paths -> paths |> Enum.map(&Path.dirname/1) |> Enum.min_by(&String.length/1)
      end

    %{base_dir: base_dir, entry_file: List.first(entries)}
  end

  defp build(%{} = node, path, context) do
    name = Map.get(node, "name", "")
    kind = Map.get(node, "kind", 0)
    children = Map.get(node, "children", [])

    own_path = if kind in @container_kinds, do: path ++ [name], else: path

    functions =
      children
      |> Enum.filter(&function_node?/1)
      |> Enum.map(&to_function(&1, context))

    types =
      children
      |> Enum.filter(&type_node?/1)
      |> Enum.map(&to_type(&1, context))

    properties =
      for %{
            "id" => id,
            "kind" => 1024,
            "name" => name,
            "type" => %{"type" => "reference", "target" => target}
          } = property <-
            children,
          kind == 128,
          is_integer(target) do
        %{
          id: id,
          name: name,
          target: target,
          definition: property |> Spec.property() |> Spec.text(),
          spec: Spec.property(property),
          source: source(property, context),
          doc: summary_parts(property)
        }
      end

    own_modules =
      if functions != [] or types != [] or properties != [] do
        [
          %{
            id: Map.fetch!(node, "id"),
            kind: kind,
            path: own_path,
            doc: summary_parts(node),
            source: module_source(node, functions, context),
            functions: functions,
            types: types,
            properties: properties
          }
        ]
      else
        []
      end

    nested =
      children
      |> Enum.reject(&(function_node?(&1) or interface_node?(&1)))
      |> Enum.flat_map(&build(&1, own_path, context))

    own_modules ++ nested
  end

  defp place_property_apis(modules) do
    owners =
      for module <- modules, property <- module.properties, reduce: %{} do
        owners ->
          owner = {module.path, property.name}
          Map.update(owners, property.target, [owner], &[owner | &1])
      end

    Enum.map(modules, fn module ->
      case {module.kind, owners[module.id]} do
        {@type_alias_kind, [{path, name}]} ->
          %{module | path: path ++ alias_segments(name)}

        _ ->
          module
      end
    end)
  end

  defp module_source(node, functions, context) do
    cond do
      source = source(node, context) -> source
      context.entry_file -> %{file: context.entry_file, line: 1}
      true -> Enum.find_value(functions, & &1.source)
    end
  end

  defp source(node, context) do
    case Map.get(node, "sources", []) do
      [%{"fileName" => file, "line" => line} | _] ->
        %{file: Path.join(context.base_dir, file), line: line}

      _ ->
        nil
    end
  end

  # Resolve the namespace used for all exports: an explicit
  # `:root_module` override, otherwise the project name, as Elixir-alias segments.
  defp root_segments(nil, decoded), do: decoded |> Map.get("name", "Api") |> alias_segments()

  defp root_segments(root_module, _decoded) when is_binary(root_module),
    do: alias_segments(root_module)

  defp alias_segments(name) do
    name
    |> String.replace(~r|^@[^/]+/|, "")
    |> String.split(~r|[./_-]|, trim: true)
    |> Enum.map(&Macro.camelize/1)
    |> case do
      [] -> ["Api"]
      segments -> segments
    end
  end

  defp function_node?(%{"kind" => kind}) when kind in [@interface_kind, @type_alias_kind],
    do: false

  defp function_node?(%{"signatures" => signatures}) when is_list(signatures), do: true
  defp function_node?(_), do: false

  defp interface_node?(%{"kind" => @interface_kind}), do: true
  defp interface_node?(_), do: false

  defp type_node?(%{"kind" => kind}), do: kind in [@interface_kind, @type_alias_kind]

  defp to_function(node, context) do
    signatures = Map.get(node, "signatures", [])
    parsed_signatures = Enum.map(signatures, &to_signature/1)

    name =
      case signatures do
        [%{"name" => n} | _] -> n
        _ -> Map.get(node, "name", "")
      end

    %{
      id: Map.get(node, "id"),
      name: name,
      async: Enum.any?(parsed_signatures, &promise_return?/1),
      source: source(node, context),
      signatures: parsed_signatures
    }
  end

  defp to_signature(signature) do
    comment = Map.get(signature, "comment") || %{}

    block_tags =
      for tag <- Map.get(comment, "blockTags", []),
          do: {Map.get(tag, "tag", ""), Map.get(tag, "content", [])}

    %{
      spec: Spec.signature(signature, Map.get(signature, "name", "")),
      comment: Map.get(comment, "summary", []),
      block_tags: block_tags,
      parameters: to_parameters(Map.get(signature, "parameters", [])),
      type_parameters: type_parameter_names(signature),
      return_type: type_string(Map.get(signature, "type"))
    }
  end

  defp type_parameter_names(signature) do
    for parameter <- Map.get(signature, "typeParameters", []), do: Map.get(parameter, "name", "")
  end

  defp to_parameters(parameters) do
    Enum.map(parameters, fn parameter ->
      flags = Map.get(parameter, "flags", %{})

      %{
        name: Map.get(parameter, "name", ""),
        type: type_string(Map.get(parameter, "type")),
        rest: Map.get(flags, "isRest", false),
        optional: Map.get(flags, "isOptional", false),
        default: Map.get(parameter, "defaultValue"),
        doc: summary_parts(parameter)
      }
    end)
  end

  defp to_type(node, context) do
    properties =
      for %{"kind" => 1024} = child <- Map.get(node, "children", []), do: to_property(child)

    %{
      id: Map.get(node, "id"),
      name: Map.get(node, "name", ""),
      doc: summary_parts(node),
      source: source(node, context),
      definition: node |> Spec.definition() |> Spec.text(),
      spec: Spec.definition(node),
      properties: properties
    }
  end

  defp to_property(node) do
    flags = Map.get(node, "flags", %{})

    %{
      name: Map.fetch!(node, "name"),
      type: type_string(Map.get(node, "type")),
      optional: Map.get(flags, "isOptional", false),
      readonly: Map.get(flags, "isReadonly", false),
      doc: summary_parts(node)
    }
  end

  defp summary_parts(node) do
    case Map.get(node, "comment") do
      %{"summary" => summary} when is_list(summary) -> summary
      _ -> nil
    end
  end

  @doc """
  A parameter carrying a default value is optional at the call site even though
  TypeDoc does not set `isOptional` on it.
  """
  def optional_parameter?(parameter), do: parameter.optional or parameter.default != nil

  @doc """
  The name a TS type is addressable under.

  ExDoc resolves `t:Mod.name/0` references with Elixir's parser, which reads a
  capitalised name as an alias rather than a type. So `ClientOpts` has to be
  registered as `client_opts`; the original name still appears in the heading and
  in `{@link}` link text.
  """
  def type_name(name), do: Macro.underscore(name)

  @doc """
  The arity a function is documented at: the widest parameter list across its
  overloads. A rest parameter counts as one.
  """
  def arity(function) do
    function.signatures |> Enum.map(&length(&1.parameters)) |> Enum.max()
  end

  # TypeDoc node id -> the ExDoc reference a `{@link}` to it should resolve to.
  defp index(modules) do
    Enum.reduce(modules, %{}, fn module, index ->
      prefix = Enum.join(module.path, ".")
      index = Map.put_new(index, module.id, prefix)

      index =
        Enum.reduce(module.functions, index, fn function, index ->
          Map.put(index, function.id, "#{prefix}.#{function.name}/#{arity(function)}")
        end)

      index =
        Enum.reduce(module.properties, index, fn property, index ->
          Map.put(index, property.id, "#{prefix}.#{property.name}/0")
        end)

      Enum.reduce(module.types, index, fn type, index ->
        Map.put(index, type.id, "t:#{prefix}.#{type_name(type.name)}/0")
      end)
    end)
  end

  defp render(module, index, module_index) do
    %{
      module
      | doc: markdown(module.doc, index),
        functions: Enum.map(module.functions, &render_function(&1, index)),
        types: Enum.map(module.types, &render_type(&1, index, module_index)),
        properties:
          for property <- module.properties,
              link_target = module_index[property.target] || index[property.target] do
            {reference, title} =
              case link_target do
                {reference, title} -> {reference, title}
                reference -> {reference, property.name}
              end

            doc = markdown(property.doc, index)
            link = "[`#{title}`](`#{reference}`)"

            %{
              property
              | doc: Enum.join(Enum.reject([doc, link], &is_nil/1), "\n\n"),
                spec: Spec.resolve(property.spec, index)
            }
          end
    }
  end

  defp render_function(function, index) do
    signatures =
      Enum.map(function.signatures, fn signature ->
        %{
          signature
          | spec: Spec.resolve(signature.spec, index),
            comment: markdown(signature.comment, index),
            block_tags:
              for({tag, parts} <- signature.block_tags, do: {tag, markdown(parts, index)}),
            parameters: Enum.map(signature.parameters, &render_doc(&1, index))
        }
      end)

    %{function | signatures: signatures}
  end

  defp render_type(type, index, module_index) do
    doc = markdown(type.doc, index)

    doc =
      if link_target = module_index[type.id] do
        {reference, title} = link_target
        link = "See [`#{title}`](`#{reference}`) for methods."
        Enum.join(Enum.reject([doc, link], &is_nil/1), "\n\n")
      else
        doc
      end

    %{
      type
      | doc: doc,
        spec: Spec.resolve(type.spec, index),
        properties: Enum.map(type.properties, &render_doc(&1, index))
    }
  end

  defp render_doc(item, index), do: %{item | doc: markdown(item.doc, index)}

  @doc """
  Joins TypeDoc comment parts into markdown, resolving `{@link}` tags against
  `index`. Returns `nil` for an empty comment.
  """
  def markdown(nil, _index), do: nil

  def markdown(parts, index) when is_list(parts) do
    case parts |> Enum.map_join("", &part_text(&1, index)) |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  @link_tags ["@link", "@linkcode", "@linkplain"]

  defp part_text(%{"kind" => "inline-tag", "tag" => tag, "text" => text} = part, index)
       when tag in @link_tags do
    case Map.fetch(index, Map.get(part, "target")) do
      {:ok, reference} -> "[`#{text}`](`#{reference}`)"
      :error -> "`#{text}`"
    end
  end

  defp part_text(%{"text" => text}, _index) when is_binary(text), do: text
  defp part_text(_part, _index), do: ""

  def signature_string(signature, name, async \\ false) do
    signature.spec |> Spec.rename(name) |> Spec.async(async) |> Spec.text()
  end

  def heading_string(signature, name, async \\ false) do
    params = Enum.map_join(signature.parameters, ", ", &render_heading_parameter/1)
    async_prefix("#{name}(#{params})", async)
  end

  defp render_heading_parameter(%{rest: true} = parameter), do: "..." <> parameter.name

  defp render_heading_parameter(%{default: default} = parameter) when is_binary(default),
    do: "#{parameter.name} = #{default}"

  defp render_heading_parameter(%{optional: true} = parameter), do: parameter.name <> "?"
  defp render_heading_parameter(parameter), do: parameter.name

  defp promise_return?(%{return_type: "Promise"}), do: true
  defp promise_return?(%{return_type: "Promise<" <> _}), do: true
  defp promise_return?(_signature), do: false

  defp async_prefix(declaration, true), do: "async " <> declaration
  defp async_prefix(declaration, false), do: declaration

  defp type_string(type), do: type |> Spec.type() |> Spec.text()
end
