defmodule IsomerWeb.CoreComponents do
  @moduledoc "Minimal shared HEEx components."
  use Phoenix.Component

  alias Phoenix.Flash
  alias Phoenix.LiveView.JS

  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr(:flash, :map, required: true)
  attr(:kind, :atom, values: [:info, :error], required: true)

  def flash(assigns) do
    assigns = assign(assigns, :msg, Flash.get(assigns.flash, assigns.kind))

    ~H"""
    <div
      :if={@msg}
      id={"flash-#{@kind}"}
      class={"flash flash-#{@kind}"}
      role="alert"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "#flash-#{@kind}")}
    >
      {@msg}
    </div>
    """
  end
end
