# End-to-end findings: real TypeScript project in an ExDoc site

Setup: `example/` made into a Mix project (`mix.exs`, `lib/example_app/server.ex`),
`mix docs` aliased to `["ts_beams out.json --root-module ExampleLib", "docs"]`,
ExDoc from `../../ex_doc`, plugin from `..`. One build, one site, in `example/doc/`.

Nothing in `ex_doc` or `ex_doc_js` was modified. Everything below was observed in
the generated HTML.

**Status:** every finding below has since been fixed, except the *variadic arity
range*, which is a limit of ExDoc's arity model rather than a bug. The sections
describe the state as first observed; jump to
[After the fixes](#after-the-fixes) for the current output.

## Verdict

The pipeline works end to end. Every structural claim in the design doc holds:
the sidebar splits, the fake `.beam` route through the plugin, cross-language
links resolve, `defaults: N` synthesizes arity aliases. What does not hold up is
**doc-comment fidelity**: roughly half the content of a typical TSDoc comment is
silently dropped before it ever reaches ExDoc, and the type renderer degrades
non-trivial types to `unknown`/`object`. Those are `ex_doc_js` gaps, not ExDoc
gaps.

## Required checks

| Check | Result |
| --- | --- |
| JavaScript-group module with all six functions | **PASS** — `ExampleLib` in group `JavaScript` with `compactMap/2, connect/0, create/2, format/2, send/1, sum/1` |
| `create/2` + `create/1` | **PASS** — `id="create/2"` with `<span id="create/1">` alias |
| `format/2` + `format/1` | **FAIL** — only `format/2`. See below. |
| `sum` variadic | **PASS, with a caveat** — `sum/1` + `sum/0` alias, `<span class="note">(variadic)</span>` renders; but see "variadic arity range" below |
| `compactMap/2` | **PASS** (arity correct; signature degraded, see below) |
| Signatures verbatim | **PARTIAL** — correct for `create`/`format`/`sum`/`send`; wrong for `connect`/`compactMap` |
| Elixir module in own sidebar section | **PASS** — `ExampleApp.Server` in group `Elixir` |
| Elixir → TS reference resolves | **PASS** — `href="ExampleLib.html#create/2"`, `#create/1`, `#send/1` |

### `format/1` is missing — the one hard failure

`ExDocJs.BeamGenerator.required_count/1` counts a parameter as optional only when
`flags.isOptional` or `flags.isRest` is set. TypeDoc represents `precision = 2`
(a *default value*, not an optional param) as `"defaultValue": "2"` with **empty
flags**. So `min_required = 2`, `defaults = 0`, no alias.

The rendered signature is also wrong as a result: `format(value: number,
precision: number): string` — the `= 2` is gone and nothing marks it optional.

The generator needs to treat `defaultValue` as optional, in both
`required_count/1` and `Typedoc.render_parameter/1`. This is the difference
between TS `?` and TS `=`; the generator only knows about `?`.

The `ExampleLib.format/1` probe in `ExampleApp.Server`'s `@moduledoc` correctly
produced a dangling-reference warning, which is how this surfaces to an author.

### Variadic arity range — only resolves downward

`ExampleLib` registers exactly two anchors for `sum`: `sum/1` and `sum/0`. A rest
param is counted as one parameter and then `defaults: 1` synthesizes the arities
*below* it. But the natural way to cite a variadic call is
`` `ExampleLib.sum/3` `` — and that will not resolve, nor will any arity above 1.

This is a limit of ExDoc's arity model rather than a bug: `defaults: N` expresses
a downward range, and a rest param needs an unbounded upward one. There is no
encoding that fixes it. It just means authors must cite variadics at arity 1 (or
0), which is unintuitive and fails silently with a dangling-reference warning.

## The risky shapes, tested explicitly

### Interfaces (`Client`, `ClientOpts`) — dropped entirely

They do not appear in the docs. No page, no sidebar entry, no search entry, no
anchor. The only occurrence of the string `ClientOpts` anywhere in `doc/` is as
inert text inside `create`'s signature heading.

Cause: `ExDocJs.Typedoc.build/3` emits a module only when a node has children
with a `"signatures"` key. Interface kind `256` is in `@container_kinds`, so it
recurses, but its members are kind `1024` properties with no `"signatures"` —
`functions == []`, no module emitted, and the recursion result is discarded.

This is the largest structural gap. A TS SDK's types *are* its API surface; a
site that documents six functions and none of the shapes they take or return is
half a reference. `create(name: string, opts?: ClientOpts): Client` names two
types the reader cannot click or look up.

### `{@link ...}` inline tags — silently flattened to bare text

Probe added to `connect`'s summary: `Must happen before {@link send}.`

Rendered: `Must happen before send.` — plain text, no `<a>`, no `<code>`.

Cause: `Typedoc.part_text/1` matches any comment part carrying a `"text"` key.
TypeDoc's inline-tag part is `%{"kind" => "inline-tag", "tag" => "@link", "text"
=> "send", "target" => 16}` — it *has* a `"text"` key, so the clause matches, the
tag and the resolved `target` id are thrown away, and the word survives as prose.
It fails quietly: the doc still reads fine, the link is just gone. The `target`
field is a resolved TypeDoc id, so this is recoverable — the information needed
to emit a working `ExampleLib.send/1` reference is present in the JSON and being
discarded.

Same loss applies to `{@link create}` / `{@link connect}` in the `Client`
interface comment and in `send`'s `@throws`.

### Backticked Elixir-alias reference in a TS doc comment — **works**

Probe added to `create`'s summary: ``The returned client is inert until
`ExampleLib.connect/0` is called on it.``

Rendered: `<a href="#connect/0"><code class="inline">ExampleLib.connect/0</code></a>`.

The delegation of `autolink_doc/2` to `ExDoc.Language.Elixir` does exactly what
the design doc predicted, and it works because the module is named as an Elixir
alias. This is the practical workaround for the `{@link}` gap today — write TS
doc comments in ExDoc reference syntax rather than TSDoc syntax — but that is a
bad thing to ask of TypeScript authors.

### TSDoc block tags — dropped

Not on the original checklist, but it is the biggest content loss. Every
`@param`, `@returns`, and `@throws` in the example source is absent from the
output. `create`'s doc renders as two sentences; its three `@param`/`@returns`
lines are gone. Compare source `client.ts` against the rendered `create/2`.

Cause: `Typedoc.comment_text/1` only reads `comment["summary"]` and never
`comment["blockTags"]`. For real TS code, where parameter semantics live almost
entirely in `@param`, this drops most of the prose.

### Module doc — the JavaScript landing page has no prose at all

`ExampleLib.html` goes straight from the `<h1>` to the Summary table. No
description, no overview, nothing. For a real SDK this is the first page a reader
lands on.

Cause is a sibling of the block-tag gap: TypeDoc puts the project description in
the root node's `readme` field (visible in the root JSON keys), but
`Typedoc.comment_text/1` only ever reads a `comment` key, and the kind-1 Project
node has none. So `or_none(module.doc)` yields `:none`. Second case of "the prose
is sitting in the JSON and nothing reads it".

### Source links — all broken, all point at line 1

Every "View Source" icon on the TS page, module and function alike, links to:

```
https://github.com/example/ex_doc_js/blob/main/example/ExampleLib.ts#L1
```

Two independent bugs, both in `ex_doc_js`:

1. `ExDocJs.ExDoc.TypeScript.module_data/3` hardcodes `source_file: "#{id}.ts"`.
   `ExampleLib.ts` does not exist — the real sources are `src/client.ts` and
   `src/utils.ts`, and one generated module is fed by both.
2. `BeamGenerator.function_entry/1` hardcodes anno `1` for every entry, and
   `doc_data/2` sets `source_file: nil`, so nothing can override it per function.

TypeDoc supplies the truth: each signature has `sources: [{fileName, line}]`.
`connect` is at `client.ts:46`, `compactMap` at `utils.ts:31`. Nothing reads it.
The generator's own JSON has what it needs.

Because one Elixir-alias module aggregates functions from several `.ts` files,
per-function `source_file` is required — a module-level path cannot be correct.

### Type rendering — degrades on anything non-trivial

Report this per function, not as one boolean:

| Rendered | Actual TS | |
| --- | --- | --- |
| `create(name: string, opts?: ClientOpts): Client` | same | correct |
| `sum(...nums: number[]): number` | same | correct |
| `send(payload: string): Promise` | `Promise<void>` | type arguments dropped |
| `connect(): Promise` | `Promise<void>` | type arguments dropped |
| `format(value: number, precision: number): string` | `precision = 2` | default lost |
| `compactMap(items: unknown, fn: object): U[]` | `<T, U>(items: readonly T[], fn: (item: T, index: number) => U \| null \| undefined): U[]` | badly degraded |

`Typedoc.type_string/1` has no clause for `typeOperator` (so `readonly T[]` hits
the `_` fallback → `unknown`), returns a bare `"object"` for `reflection` (so the
callback type vanishes even though its full signature is in the JSON), and never
reads `typeArguments` (so every generic renders as its bare constructor). Type
parameters `<T, U>` are not rendered at all.

`compactMap(items: unknown, fn: object)` is worse than no signature — it is
actively misleading about the call shape.

### ExDoc warnings during the build

Two groups.

**Expected and correct (1 distinct, emitted twice):**

```
warning: documentation references function "ExampleLib.format/1" but it is undefined or private
```

That is my deliberate probe, and the duplication is just the HTML and EPUB
formatter passes. Notably, this is real proof the cross-language ref table works:
ExDoc validated an Elixir-page reference *against the TS module's actual arities*
and correctly rejected one that doesn't exist.

**Unexpected — `ex_doc_js` compiles with the behaviour unresolved:**

```
warning: @behaviour ExDoc.Language does not exist (in module ExDocJs.ExDoc.TypeScript)
warning: got "@impl true" for function module_data/3 but no behaviour specifies such callback   (×11)
warning: ExDoc.Language.Elixir.autolink_doc/2 is undefined                                       (×3)
```

15 warnings, on **every** `mix docs` run. Cause: `ex_doc_js/mix.exs` declares
`{:ex_doc, path: "../ex_doc", only: [:dev, :test]}`. `only:` deps of a dependency
are not loaded by the parent project, so Mix has no ordering edge from
`ex_doc_js` to `ex_doc` and compiles `ex_doc_js` **first** — the build log shows
`Generated ex_doc_js app` before `Generated ex_doc app`.

Consequences:

- The `@behaviour` is never actually checked. The 11 callbacks are unverified at
  compile time; a signature drift in `ExDoc.Language` would only show up as a
  runtime `UndefinedFunctionError` mid-build.
- The unresolved remote calls are recorded as a missing-module dependency, so
  Mix recompiles `ex_doc_js` on every single run and re-prints all 15 warnings.
  Anyone adopting this will see a permanently noisy build.
- It works at runtime purely because both modules are loaded by the time
  `mix docs` executes.

Per the constraints I did not patch this; the fix belongs in `ex_doc_js/mix.exs`
(drop `only:`, or add `runtime: false`).

**No warnings from ExDoc itself about the custom language.** The `:languages`
config validated cleanly, dispatch to the plugin was silent, and nothing in the
retriever or the formatters complained about a third language. The ExDoc-side
seam is the part of this that behaved best.

## Guesses and workarounds

- **`npm run typedoc` is broken in `example/package.json`.** The script is
  `typedoc --json out.json` with no entry point and no `typedoc.json`; running it
  emits `No entry points were provided` and writes an **empty** project (no
  `children`), which would produce zero modules. I ran
  `typedoc --json out.json --name ExampleLib src/index.ts` instead to reproduce
  the committed shape. The committed `out.json` must have been produced with
  arguments not recorded in the repo — and since `out.json` is gitignored, a
  fresh clone could not reproduce the build at all. The script now carries those
  arguments. `--name ExampleLib` also matters: without
  it the project name is `ex-doc-js-example`, which `Typedoc.alias_segments/1`
  camelizes into a different root module. I passed `--root-module ExampleLib`
  explicitly so the alias does not depend on it.
- **`override: true` on the `ex_doc` path dep** in `example/mix.exs`, since both
  `example` and `ex_doc_js` name it.
- The `docs:` alias is self-named (`docs: [..., "docs"]`); Mix resolves the
  trailing `"docs"` to the real task, no recursion. Already the pattern in
  `ex_doc_js`'s own `mix.exs`.
- I edited `example/src/client.ts` to add the two probes (the backticked
  `ExampleLib.connect/0` reference and a `{@link send}` in a *summary* — the
  pre-existing `{@link}` tags were all in block tags or interface comments, both
  of which are dropped before the tag question can even be asked).

## What to fix first, in order

1. **`defaultValue` ⇒ optional** in `required_count/1` and `render_parameter/1`.
   One-line-ish, and it is the only outright failure of a stated requirement.
2. **Read `sources[]`** for per-function `source_file`/`source_line`. Every
   source link on the site is currently broken.
3. **Read `blockTags`, and the project `readme` for the module doc.** Largest
   prose loss, no design work needed.
4. **`type_string/1`: `typeArguments`, `typeOperator`, reflection signatures.**
5. **`{@link}` → real reference,** using the `target` id already in the JSON.
6. **Emit interfaces as modules** (properties as entries, or a types group).
   Largest design question of the six; the rest are localized.

## After the fixes

All seven were fixed in `ex_doc_js` (nothing in ExDoc needed to change).
Interfaces became `:type` entries on the enclosing module rather than modules of
their own. `mix docs` from `example/` now emits **zero warnings**.

| Was | Now |
| --- | --- |
| `format/2` only | `format/2` + `format/1`, signature `format(value: number, precision: number = 2): string` |
| `connect(): Promise` | `connect(): Promise<void>` |
| `compactMap(items: unknown, fn: object): U[]` | `compactMap<T, U>(items: readonly T[], fn: (item: T, index: number) => undefined \| null \| U): U[]` |
| interfaces absent | `t:client/0` and `t:client_opts/0` in a **Types** group, with their properties |
| `{@link send}` → the word `send` | `<a href="#send/1">send</a>` |
| every source link `ExampleLib.ts#L1` | `src/client.ts#L35`, `src/utils.ts#L29`, … — real file, real line |
| `@param`/`@returns`/`@throws` dropped | rendered as **Parameters** / **Returns** sections |
| JS landing page had no prose | project `readme` renders as the module doc |
| 15 compile warnings per run | none; `ex_doc_js` now compiles after ExDoc |

Cross-references from `ExampleApp.Server` that resolve: `create/2`, `create/1`,
`format/1`, `send/1`, and `t:ExampleLib.client_opts/0`.

Still open: the **variadic arity range**. `sum` registers `sum/0` and `sum/1`
only, so `ExampleLib.sum/3` does not resolve. Unfixable in `ex_doc_js` —
`defaults: N` expresses a downward range and a rest parameter needs an unbounded
upward one.

### What the fixes are

1. **`defaultValue` ⇒ optional.** `Typedoc.optional_parameter?/1` treats a
   defaulted parameter as optional, so it stops counting toward
   `min_required`, and `render_parameter/1` prints `= 3`.
2. **Per-entry source.** `sources[].fileName` is relative to TypeDoc's base path;
   the project root path comes from `files.entries`, whose common directory is
   that base path. Each entry carries `source_file` in its metadata, and the
   plugin reads it in `doc_data/2` — necessary because one module aggregates
   functions from several `.ts` files.
3. **Block tags and `readme`.** Rendered as `## Returns` / `## Throws` sections;
   `@param` docs live on the parameters themselves and become a `## Parameters`
   list. A Project node has no `comment`, so its `readme` is the module doc.
4. **`type_string/1`** gained `typeArguments`, `typeOperator`, intersections,
   `null` literals, and reflections with call signatures; signatures render their
   `typeParameters`.
5. **`{@link}`.** `Typedoc.parse/2` is now two passes: build modules, then index
   TypeDoc node ids to references, then render comments. A resolved tag becomes
   `` [`text`](`Mod.fun/2`) `` — display text preserved, target correct. An
   unresolved one degrades to inline code rather than a dangling reference.
6. **Interfaces** become `{:type, name, 0}` entries; the plugin gained a `:type`
   clause with `id_key: "t:"` and a `Types` default group.
7. **Dep ordering.** `{:ex_doc, path: "../ex_doc", runtime: false}` instead of
   `only: [:dev, :test]`, so parent projects compile ExDoc first and the
   `@behaviour` is actually checked.

### Two constraints discovered while fixing

**TS type names must be registered lowercase.** ExDoc resolves `t:Mod.name/0`
through Elixir's parser, and `parse_function("Client")` parses `Client` as an
alias — it returns the name `:__aliases__`, so the lookup misses and ExDoc warns
`references type "t:ExampleLib.Client/0" but it is undefined`.

So interfaces register under `Macro.underscore/1` of their name: `ClientOpts`
becomes `t:ExampleLib.client_opts/0`. The TS name survives in the heading
(`interface ClientOpts`) and in `{@link}` link text, so readers never see the
underscored form — but an author hand-writing a reference from an Elixir page
must use it. This is inherent to borrowing Elixir's reference parser, which is
what makes cross-language links work at all; it is the price of that trade.

**A module's source path cannot be nil.** The first attempt at fix 2 made the
plugin read `source_file` with `Map.fetch!/2`, on the assumption that a module
always has a location. It doesn't: `typedoc --excludeSources` emits no `sources`
at all, and ExDoc calls `Path.relative_to_cwd/1` on the module path without a nil
clause — so the build died with a `KeyError`. The plugin keeps a stand-in
`Mod.ts` path for that case. It now appears only when TypeDoc supplied no
locations whatsoever, rather than unconditionally as before.
