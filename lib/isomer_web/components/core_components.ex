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
    <.link
      navigate={@to}
      class={[
        "inline-flex items-center gap-2.5 text-slate-900 no-underline dark:text-slate-100",
        @class
      ]}
    >
      <span class="inline-flex h-9 w-9 items-center justify-center rounded-[10px] bg-[#f4fbfd] ring-1 ring-slate-200/80 dark:bg-slate-800 dark:ring-slate-700">
        <img src={~p"/images/isomer-mark.svg"} alt="" class="h-7 w-7" />
      </span>
      <span class="font-[family-name:var(--font-display)] text-xl font-semibold tracking-wide">
        Isomer
      </span>
    </.link>
    """
  end
end
