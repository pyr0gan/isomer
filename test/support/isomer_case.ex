defmodule Isomer.Case do
  @moduledoc """
  Shared ExUnit case template for offline unit tests (no live Surreal).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ExUnit.Assertions
    end
  end
end
