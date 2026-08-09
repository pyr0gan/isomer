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
        <svg
          class="github-gusset__icon"
          viewBox="0 0 98 96"
          width="40"
          height="39"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z"
          />
        </svg>
        <span class="github-gusset__label">GitHub</span>
      </span>
      <span class="github-gusset__bubble" role="tooltip">visit us on GitHub</span>
    </a>
    """
  end
end
