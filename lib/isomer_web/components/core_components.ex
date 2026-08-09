defmodule IsomerWeb.CoreComponents do
  @moduledoc "App-specific HEEx helpers (logo, flashes bridged via Petal toasts)."
  use Phoenix.Component

  use PetalComponents
  use Phoenix.VerifiedRoutes,
    endpoint: IsomerWeb.Endpoint,
    router: IsomerWeb.Router,
    statics: IsomerWeb.static_paths()

  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <.toast_group flash={@flash} position="top-right" />
    """
  end

  attr(:class, :any, default: nil)
  attr(:to, :string, default: "/")

  def brand_logo(assigns) do
    ~H"""
    <.link navigate={@to} class={["inline-flex items-center gap-2 no-underline", @class]}>
      <img src={~p"/images/isomer-logo.svg"} alt="Isomer" class="h-9 w-auto" />
    </.link>
    """
  end
end
