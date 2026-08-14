defmodule ExDocJsTest do
  use ExUnit.Case
  doctest ExDocJs

  test "greets the world" do
    assert ExDocJs.hello() == :world
  end
end
