defmodule ExampleApp.Server do
  @moduledoc """
  The Elixir side of the example, talking to the TypeScript SDK.

  Browser clients are built with `ExampleLib.create/2`, or with
  `ExampleLib.create/1` when the default options are good enough. Options are
  documented as `t:ExampleLib.client_opts/0`.

  `ExampleLib.format/1` is the synthesized lower arity of a TS parameter that
  carries a default value rather than an optional marker.
  """

  @doc """
  Encodes a payload for the transport.

  The result is what `ExampleLib.send/1` expects on the wire.
  """
  def encode(payload) when is_binary(payload), do: payload
end
