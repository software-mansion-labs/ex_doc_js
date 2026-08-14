# ExampleLib

A small TypeScript transport client, used to exercise the `ex_doc_js` pipeline
end to end against real `typedoc --json` output.

Create a client with `create`, `connect` it, then `send` messages. `sum`,
`format` and `compactMap` are plain utilities that cover the awkward shapes:
a rest parameter, a defaulted parameter, and a generic higher-order function.
