# ExDocJs

ExDocJs adds TypeScript modules to the same documentation site as an Elixir
project. It ships pinned TypeDoc and TypeScript modules, so applications only
need Node.js and an Elixir configuration.

## Installation

Add `ex_doc_js` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_doc_js, "~> 0.1.0", only: :dev, runtime: false}
  ]
end
```

Configure ExDoc lazily and point ExDocJs at the public TypeScript entry files:

```elixir
def project do
  [
    app: :my_app,
    version: "1.0.0",
    deps: deps(),
    docs: fn -> docs() end
  ]
end

defp docs do
  [
    main: "MyApp",
    extras: ["README.md"]
  ]
  |> ExDocJs.configure(entry_points: ["assets/js/index.ts"])
end
```

Generate the complete site with the normal command:

```console
mix docs
```

The zero-argument function delays TypeScript generation until documentation
dependencies have been compiled. `ExDocJs.configure/2` adds to the existing
options, so extra pages, formatters, callbacks, module groups, and other
language adapters remain configured.

## Options

`entry_points` is required and accepts one or more TypeScript files. The
following options are available:

- `root_module` sets the namespace for all JavaScript pages. TypeDoc's project
  name is used when it is omitted. With `root_module: "JS"`, standalone exports
  appear on `JS`, and a `Popcorn` class appears on `JS.Popcorn`.
  An object type alias used by exactly one class property gets a page under
  that class: `genserver: GenServer` becomes `JS.Popcorn.Genserver`.
  Shared and standalone aliases keep their names under the namespace.
- `tsconfig` selects a TypeScript configuration file.
- `group` changes the TypeScript sidebar group. It defaults to `"JavaScript"`.
  Set it to `false` to keep the existing grouping unchanged.

ExDocJs raises if another language adapter already owns `:typescript`. It does
not replace that adapter or a user-supplied `source_url_pattern`.

Exported interfaces and type aliases appear in the containing page's Types
section. Aliases with methods also link to their callable API page.

## Bundled TypeDoc

The package includes TypeDoc 0.28.20 and TypeScript 6.0.3 under `priv/typedoc`.
Node.js must be available on the system path. ExDocJs does not download packages
or invoke npm while generating documentation.

Maintainers refresh the bundled runtime after changing
`vendor/typedoc/package.json` and its lockfile:

```console
mix ex_doc_js.vendor
```

The development task performs a clean production install and copies the runtime
into the gitignored `priv/typedoc` directory. Run it before building a release;
the generated runtime and dependency license files are included in the package.
