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
      <span class="text-xl font-bold tracking-wide">
        Isomer
      </span>
    </.link>
    """
  end

  attr(:href, :string, default: "https://github.com/pyr0gan/isomer")
  attr(:class, :any, default: nil)

  def github_gusset(assigns) do
    ~H"""
    <a
      href={@href}
      class={["github-gusset", @class]}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="GitHub — visit us on GitHub"
    >
      <span class="github-gusset__face" aria-hidden="true">
        <span class="github-gusset__band">
          <svg
            class="github-gusset__icon"
            viewBox="0 0 16 16"
            width="16"
            height="16"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
          </svg>
          <span class="github-gusset__label">GitHub</span>
        </span>
      </span>
      <span class="github-gusset__bubble" role="tooltip">visit us on GitHub</span>
    </a>
    """
  end
end
