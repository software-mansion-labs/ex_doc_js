defmodule ExDocJs.Spec do
  @moduledoc false

  def text({:reference, name, _target}), do: name
  def text({:signature, name, body}), do: text([name, body])
  def text(parts) when is_list(parts), do: Enum.map_join(parts, &text/1)
  def text(part) when is_binary(part), do: part

  def rename({:signature, _name, body}, name), do: {:signature, name, body}

  def async(spec, false), do: spec
  def async(spec, true), do: ["async ", spec]

  def html({:reference, name, reference}, config) do
    url =
      reference &&
        ExDoc.Autolink.url(reference, :regular_link, %{config | force_module_prefix: false})

    if url,
      do: [~s(<a href="), ExDoc.Utils.h(url), ~s(">), ExDoc.Utils.h(name), "</a>"],
      else: ExDoc.Utils.h(name)
  end

  def html({:signature, name, body}, config), do: html([name, body], config)
  def html(parts, config) when is_list(parts), do: Enum.map(parts, &html(&1, config))
  def html(part, _config) when is_binary(part), do: ExDoc.Utils.h(part)

  def resolve({:reference, name, target}, index),
    do: {:reference, name, Map.get(index, target)}

  def resolve({:signature, name, body}, index),
    do: {:signature, name, resolve(body, index)}

  def resolve(parts, index) when is_list(parts), do: Enum.map(parts, &resolve(&1, index))
  def resolve(part, _index) when is_binary(part), do: part

  def signature(node, name) do
    params = node |> Map.get("parameters", []) |> Enum.map(&parameter/1) |> join(", ")
    result = type(node["type"])
    return = if text(result) == "", do: [], else: [": ", result]
    {:signature, name, [type_parameters(node), "(", params, ")", return]}
  end

  def definition(node) do
    name = [node["name"], type_parameters(node)]

    case node["kind"] do
      256 ->
        ["interface ", name, " ", object(node)]

      2_097_152 ->
        ["type ", name, " = ", if(node["type"], do: type(node["type"]), else: object(node))]
    end
  end

  def property(node) do
    flags = Map.get(node, "flags", %{})
    name = property_name(node["name"])
    name = if flags["isOptional"], do: [name, "?"], else: name
    declaration = annotate(name, type(node["type"]))
    if flags["isReadonly"], do: ["readonly ", declaration], else: declaration
  end

  defp parameter(node) do
    flags = Map.get(node, "flags", %{})
    name = node["name"]
    value = type(node["type"])

    cond do
      flags["isRest"] -> ["...", annotate(name, value)]
      is_binary(node["defaultValue"]) -> [annotate(name, value), " = ", node["defaultValue"]]
      flags["isOptional"] -> annotate([name, "?"], value)
      true -> annotate(name, value)
    end
  end

  defp type_parameters(node) do
    node
    |> Map.get("typeParameters", [])
    |> Enum.map(fn parameter ->
      constraint = if parameter["type"], do: [" extends ", type(parameter["type"])], else: []
      default = if parameter["default"], do: [" = ", type(parameter["default"])], else: []
      [parameter["name"], constraint, default]
    end)
    |> generics()
  end

  defp object(node) do
    members =
      Enum.flat_map(Map.get(node, "children", []), fn child ->
        case child do
          %{"signatures" => signatures, "name" => name} ->
            Enum.map(signatures, &signature(&1, property_name(name)))

          _ ->
            [property(child)]
        end
      end)

    signatures = for signature <- Map.get(node, "signatures", []), do: signature(signature, "")
    body = (members ++ signatures) |> Enum.map(&["  ", indent(&1), ";"]) |> join("\n")
    ["{\n", body, "\n}"]
  end

  defp indent({:reference, _, _} = part), do: part
  defp indent({:signature, name, body}), do: {:signature, name, indent(body)}
  defp indent(parts) when is_list(parts), do: Enum.map(parts, &indent/1)
  defp indent(part) when is_binary(part), do: String.replace(part, "\n", "\n  ")

  defp property_name("[" <> _ = name), do: name

  defp property_name(name) do
    if Regex.match?(~r/^(?:[$\p{L}_][$\p{L}\p{N}_]*|\d+)$/u, name),
      do: name,
      else: Jason.encode!(name)
  end

  defp annotate(name, value) do
    if text(value) == "", do: name, else: [name, ": ", value]
  end

  defp generics([]), do: []
  defp generics(parts), do: ["<", join(parts, ", "), ">"]
  defp join(parts, separator), do: Enum.intersperse(parts, separator)

  def type(nil), do: ""

  def type(%{"type" => kind, "name" => name}) when kind in ["intrinsic", "typeParameter"],
    do: name

  def type(%{"type" => "literal", "value" => nil}), do: "null"

  def type(%{"type" => "literal", "value" => value}) when is_binary(value),
    do: Jason.encode!(value)

  def type(%{"type" => "literal", "value" => value}), do: to_string(value)

  def type(%{"type" => "reference", "name" => name} = type) do
    [
      {:reference, name, type["target"]},
      generics(Enum.map(Map.get(type, "typeArguments", []), &type/1))
    ]
  end

  def type(%{"type" => "typeOperator", "operator" => operator, "target" => target}),
    do: [operator, " ", type(target)]

  def type(%{"type" => "array", "elementType" => element}) do
    case element do
      %{"type" => kind} when kind in ["union", "intersection"] -> ["(", type(element), ")[]"]
      _ -> [type(element), "[]"]
    end
  end

  def type(%{"type" => "union", "types" => types}), do: types |> Enum.map(&type/1) |> join(" | ")

  def type(%{"type" => "intersection", "types" => types}),
    do: types |> Enum.map(&type/1) |> join(" & ")

  def type(%{"type" => "tuple", "elements" => elements}),
    do: ["[", join(Enum.map(elements, &type/1), ", "), "]"]

  def type(%{"type" => "indexedAccess", "objectType" => object, "indexType" => index}),
    do: [type(object), "[", type(index), "]"]

  def type(%{"type" => "mapped"} = node) do
    readonly = mapped_modifier(node["readonlyModifier"], "readonly ")
    optional = mapped_modifier(node["optionalModifier"], "?")
    rename = if node["nameType"], do: [" as ", type(node["nameType"])], else: []
    parameter = [node["parameter"], " in ", type(node["parameterType"]), rename]

    [
      "{\n  ",
      readonly,
      "[",
      parameter,
      "]",
      optional,
      ": ",
      indent(type(node["templateType"])),
      ";\n}"
    ]
  end

  def type(%{"type" => "reflection", "declaration" => declaration}) do
    case Map.get(declaration, "signatures", []) do
      [signature | _] ->
        params = signature |> Map.get("parameters", []) |> Enum.map(&parameter/1) |> join(", ")
        ["(", params, ") => ", type(signature["type"])]

      [] ->
        object(declaration)
    end
  end

  def type(%{"type" => "unknown", "name" => name}), do: name
  def type(_), do: "unknown"

  defp mapped_modifier(nil, _modifier), do: ""
  defp mapped_modifier("+", modifier), do: modifier
  defp mapped_modifier("-", modifier), do: "-" <> modifier
end
