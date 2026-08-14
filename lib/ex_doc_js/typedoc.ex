defmodule ExDocJs.Typedoc do
  @moduledoc false

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
    index = index(modules)
    module_index = Map.new(modules, &{&1.id, Enum.join(&1.path, ".")})

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
          definition: property |> to_property() |> render_property(),
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
            doc: module_doc_parts(node),
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

  # A project node carries its description in `readme`, not in `comment`.
  defp module_doc_parts(node) do
    summary_parts(node) || Map.get(node, "readme")
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
      definition: type_definition(node),
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
              reference = module_index[property.target] || index[property.target] do
            doc = markdown(property.doc, index)
            link = "[`#{reference}`](`#{reference}`)"
            %{property | doc: Enum.join(Enum.reject([doc, link], &is_nil/1), "\n\n")}
          end
    }
  end

  defp render_function(function, index) do
    signatures =
      Enum.map(function.signatures, fn signature ->
        %{
          signature
          | comment: markdown(signature.comment, index),
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
      if reference = module_index[type.id] do
        link = "See [`#{reference}`](`#{reference}`) for methods."
        Enum.join(Enum.reject([doc, link], &is_nil/1), "\n\n")
      else
        doc
      end

    %{
      type
      | doc: doc,
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
    params = Enum.map_join(signature.parameters, ", ", &render_parameter/1)
    generics = generics(signature.type_parameters)

    declaration =
      case {params, signature.return_type} do
        {"", ""} -> "#{name}#{generics}()"
        {"", return} -> "#{name}#{generics}(): #{return}"
        {params, ""} -> "#{name}#{generics}(#{params})"
        {params, return} -> "#{name}#{generics}(#{params}): #{return}"
      end

    async_prefix(declaration, async)
  end

  def heading_string(signature, name, async \\ false) do
    params = Enum.map_join(signature.parameters, ", ", &render_heading_parameter/1)
    async_prefix("#{name}(#{params})", async)
  end

  defp type_definition(node) do
    name = node["name"] <> type_parameters_string(node)

    case node["kind"] do
      @interface_kind ->
        "interface #{name} " <> object_string(node)

      @type_alias_kind ->
        value = if type = node["type"], do: type_string(type), else: object_string(node)
        "type #{name} = #{value}"
    end
  end

  defp type_parameters_string(node) do
    node
    |> Map.get("typeParameters", [])
    |> Enum.map(fn parameter ->
      constraint = if type = parameter["type"], do: " extends " <> type_string(type), else: ""
      default = if type = parameter["default"], do: " = " <> type_string(type), else: ""
      parameter["name"] <> constraint <> default
    end)
    |> generics()
  end

  defp object_string(node) do
    members =
      Enum.flat_map(Map.get(node, "children", []), fn child ->
        case child do
          %{"signatures" => signatures, "name" => name} ->
            Enum.map(signatures, &signature_string(to_signature(&1), property_name(name)))

          _ ->
            [child |> to_property() |> render_property()]
        end
      end)

    signatures =
      for signature <- Map.get(node, "signatures", []) do
        signature_string(to_signature(signature), "")
      end

    body =
      Enum.map_join(members ++ signatures, "\n", fn member ->
        "  " <> String.replace(member, "\n", "\n  ") <> ";"
      end)

    "{\n#{body}\n}"
  end

  defp generics([]), do: ""
  defp generics(names), do: "<" <> Enum.join(names, ", ") <> ">"

  defp render_parameter(%{rest: true} = p), do: "..." <> annotate(p.name, p.type)

  defp render_parameter(%{default: default} = p) when is_binary(default),
    do: annotate(p.name, p.type) <> " = " <> default

  defp render_parameter(%{optional: true} = p), do: annotate(p.name <> "?", p.type)
  defp render_parameter(p), do: annotate(p.name, p.type)

  defp render_heading_parameter(%{rest: true} = parameter), do: "..." <> parameter.name

  defp render_heading_parameter(%{default: default} = parameter) when is_binary(default),
    do: "#{parameter.name} = #{default}"

  defp render_heading_parameter(%{optional: true} = parameter), do: parameter.name <> "?"
  defp render_heading_parameter(parameter), do: parameter.name

  defp render_property(property) do
    name = property_name(property.name)
    name = if property.optional, do: name <> "?", else: name
    declaration = annotate(name, property.type)

    if property.readonly, do: "readonly " <> declaration, else: declaration
  end

  defp property_name("[" <> _ = name), do: name

  defp property_name(name) do
    if Regex.match?(~r/^(?:[$\p{L}_][$\p{L}\p{N}_]*|\d+)$/u, name),
      do: name,
      else: Jason.encode!(name)
  end

  defp promise_return?(%{return_type: "Promise"}), do: true
  defp promise_return?(%{return_type: "Promise<" <> _}), do: true
  defp promise_return?(_signature), do: false

  defp async_prefix(declaration, true), do: "async " <> declaration
  defp async_prefix(declaration, false), do: declaration

  defp annotate(name, ""), do: name
  defp annotate(name, type), do: "#{name}: #{type}"

  defp type_string(nil), do: ""

  defp type_string(%{"type" => "intrinsic", "name" => name}), do: name
  defp type_string(%{"type" => "typeParameter", "name" => name}), do: name
  defp type_string(%{"type" => "literal", "value" => nil}), do: "null"

  defp type_string(%{"type" => "literal", "value" => value}) when is_binary(value),
    do: Jason.encode!(value)

  defp type_string(%{"type" => "literal", "value" => value}), do: to_string(value)

  defp type_string(%{"type" => "reference", "name" => name} = type) do
    name <> generics(Enum.map(Map.get(type, "typeArguments", []), &type_string/1))
  end

  defp type_string(%{"type" => "typeOperator", "operator" => operator, "target" => target}) do
    "#{operator} #{type_string(target)}"
  end

  defp type_string(%{"type" => "array", "elementType" => element}) do
    case element do
      %{"type" => kind} when kind in ["union", "intersection"] ->
        "(" <> type_string(element) <> ")[]"

      _ ->
        type_string(element) <> "[]"
    end
  end

  defp type_string(%{"type" => "union", "types" => types}),
    do: Enum.map_join(types, " | ", &type_string/1)

  defp type_string(%{"type" => "intersection", "types" => types}),
    do: Enum.map_join(types, " & ", &type_string/1)

  defp type_string(%{"type" => "tuple", "elements" => elements}),
    do: "[" <> Enum.map_join(elements, ", ", &type_string/1) <> "]"

  defp type_string(%{"type" => "indexedAccess", "objectType" => object, "indexType" => index}),
    do: type_string(object) <> "[" <> type_string(index) <> "]"

  defp type_string(%{"type" => "mapped"} = type) do
    readonly = mapped_modifier(type["readonlyModifier"], "readonly ")
    optional = mapped_modifier(type["optionalModifier"], "?")
    rename = if name = type["nameType"], do: " as " <> type_string(name), else: ""
    parameter = type["parameter"] <> " in " <> type_string(type["parameterType"]) <> rename
    template = type_string(type["templateType"]) |> String.replace("\n", "\n  ")
    "{\n  #{readonly}[#{parameter}]#{optional}: #{template};\n}"
  end

  # A function type is a reflection whose declaration carries call signatures.
  defp type_string(%{"type" => "reflection", "declaration" => declaration}) do
    case Map.get(declaration, "signatures", []) do
      [signature | _] ->
        signature = to_signature(signature)
        params = Enum.map_join(signature.parameters, ", ", &render_parameter/1)
        "(#{params}) => #{signature.return_type}"

      [] ->
        object_string(declaration)
    end
  end

  defp type_string(%{"type" => "unknown", "name" => name}), do: name
  defp type_string(_), do: "unknown"

  defp mapped_modifier(nil, _modifier), do: ""
  defp mapped_modifier("+", modifier), do: modifier
  defp mapped_modifier("-", modifier), do: "-" <> modifier
end
