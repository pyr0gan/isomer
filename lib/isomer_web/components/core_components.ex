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

  attr(:series, :list, required: true)
  attr(:label, :string, required: true)
  attr(:value, :any, default: nil)
  attr(:suffix, :string, default: "")
  attr(:class, :any, default: nil)

  def metric_sparkline(assigns) do
    points = Isomer.OrgMetrics.sparkline_points(assigns.series)
    ready? = Isomer.OrgMetrics.sparkline_ready?(assigns.series)
    assigns = assign(assigns, points: points, ready?: ready?)

    ~H"""
    <div class={["metric-sparkline", @class]}>
      <div class="metric-sparkline__head">
        <span class="metric-sparkline__label">{@label}</span>
        <span class="metric-sparkline__value">
          {format_metric_value(@value)}{@suffix}
        </span>
      </div>
      <%= if @ready? and @points do %>
        <svg
          class="metric-sparkline__chart"
          viewBox="0 0 120 28"
          width="120"
          height="28"
          role="img"
          aria-label={"#{@label} trend"}
        >
          <polyline
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            points={@points}
          />
        </svg>
      <% else %>
        <div class="metric-sparkline__placeholder" aria-label="data required">
          data req'd
        </div>
      <% end %>
    </div>
    """
  end

  defp format_metric_value(nil), do: "—"

  defp format_metric_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 1)

  defp format_metric_value(value), do: to_string(value)

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
        <img
          class="github-gusset__icon"
          src={~p"/images/github-mark.svg"}
          width="40"
          height="39"
          alt=""
        />
        <span class="github-gusset__label">GitHub</span>
      </span>
      <span class="github-gusset__bubble" role="tooltip">visit us on GitHub</span>
    </a>
    """
  end
end
