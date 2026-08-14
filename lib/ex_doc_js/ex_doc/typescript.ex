defmodule ExDocJs.ExDoc.TypeScript do
  @moduledoc false
  @behaviour ExDoc.Language

  @impl true
  def module_data(module, docs_chunk, _config) do
    id = module |> Atom.to_string() |> String.trim_leading("Elixir.")
    {:docs_v1, anno, _, _, _, metadata, _} = docs_chunk

    %{
      module: module,
      default_groups: ["Types", "Properties", "Functions"],
      docs: docs_chunk,
      language: __MODULE__,
      id: id,
      title: id,
      type: :module,
      source_line: anno,
      # ExDoc has no nil handling for a module's source path, so a project built
      # with TypeDoc's `--excludeSources` still needs a stand-in here.
      source_file: Map.get(metadata, :source_file, "#{id}.ts"),
      source_basedir: File.cwd!(),
      nesting_info: nil,
      private: %{}
    }
  end

  @impl true
  def doc_data({{:function, _name, _arity}, anno, signature, _doc, metadata}, _module_data) do
    extra_annotations = if Map.get(metadata, :variadic, false), do: ["variadic"], else: []
    kind = Map.get(metadata, :kind, :function)

    %{
      id_key: "",
      default_group: if(kind == :property, do: "Properties", else: "Functions"),
      doc_fallback: fn -> nil end,
      extra_annotations: extra_annotations,
      signature: signature,
      source_file: Map.get(metadata, :source_file),
      source_line: anno,
      specs: Map.fetch!(metadata, :specs),
      type: kind
    }
  end

  def doc_data({{:type, _name, _arity}, anno, signature, _doc, metadata}, _module_data) do
    %{
      id_key: "t:",
      default_group: "Types",
      doc_fallback: fn -> nil end,
      extra_annotations: [],
      signature: signature,
      source_file: Map.get(metadata, :source_file),
      source_line: anno,
      specs: Map.fetch!(metadata, :specs),
      type: :type
    }
  end

  def doc_data(_entry, _module_data), do: false

  @impl true
  def autolink_doc(ast, config),
    do: ExDoc.Language.Elixir.autolink_doc(ast, %{config | language: ExDoc.Language.Elixir})

  @impl true
  def parse_module_function(string), do: ExDoc.Language.Elixir.parse_module_function(string)

  @impl true
  def parse_module(string, mode), do: ExDoc.Language.Elixir.parse_module(string, mode)

  @impl true
  def autolink_spec(spec, _config), do: ExDoc.Utils.h(spec)

  @impl true
  def format_spec(spec), do: spec

  @impl true
  def format_spec_attribute(%{type: :function}), do: "@spec"
  def format_spec_attribute(%{type: :property}), do: "@spec"
  def format_spec_attribute(%{type: :type}), do: "@type"

  @impl true
  def highlight_info, do: %{language_name: "typescript", lexer: nil, opts: []}

  @impl true
  def try_autoimported_function(_name, _arity, _mode, _config, _original_text), do: nil

  @impl true
  def try_builtin_type(_name, _arity, _mode, _config, _original_text), do: nil
end
