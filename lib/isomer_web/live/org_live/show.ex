defmodule IsomerWeb.OrgLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant
  alias Isomer.Maturity
  alias Isomer.OrgMetrics

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    org_id = Tenant.canonicalize_record_id(org_id)

    with {:ok, org} <- Tenant.get_org(socket.assigns.surreal, org_id),
         {:ok, assessments} <- Tenant.list_assessments(socket.assigns.surreal, org_id) do
      maturity =
        case Maturity.org_domain_bars(socket.assigns.surreal, assessments) do
          {:ok, bars} -> bars
          {:error, _} -> []
        end

      metrics =
        case OrgMetrics.org_panel(socket.assigns.surreal, assessments) do
          {:ok, panel} -> panel
          {:error, _} -> empty_metrics()
        end

      {ongoing, finalized} = Enum.split_with(assessments, &ongoing?/1)

      {:ok,
       assign(socket,
         page_title: org["name"],
         org: org,
         org_id: org_id,
         assessments: assessments,
         ongoing_assessments: ongoing,
         finalized_assessments: finalized,
         maturity: maturity,
         metrics: metrics,
         error: nil
       )}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Tenant.delete_org(socket.assigns.surreal, socket.assigns.org_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization deleted")
         |> push_navigate(to: ~p"/orgs")}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp ongoing?(%{"status" => status}) when status in ["complete", "archived"], do: false
  defp ongoing?(_), do: true

  defp empty_metrics do
    %{
      "has_collection" => false,
      "current" => nil,
      "series" => %{
        "yes_pct" => [],
        "unanswered" => [],
        "evidence_pct" => [],
        "time_hours" => []
      }
    }
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>{@org["name"]}</.h1>
          <.p class="isomer-lede">
            Assessments for this tenant · id …{Tenant.short_key(@org_id)}
          </.p>
        </div>
        <div class="flex flex-wrap gap-2">
          <.button
            link_type="live_redirect"
            to={~p"/orgs/#{@org_id}/assessments/new"}
            label="New assessment"
            icon="hero-plus"
          />
          <.button
            type="button"
            color="danger"
            variant="outline"
            label="Delete org"
            phx-click="delete"
            data-confirm={"Delete “#{@org["name"]}” and all its assessments? This cannot be undone."}
          />
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <div class="maturity-panels">
        <.card class="maturity-card">
          <.card_header
            title="Org maturity"
            description="Estimated from Yes answers on L1/L2 questions (newest assessment wins)."
          />
          <.card_content>
            <%= if @maturity == [] do %>
              <.p no_margin class="text-base text-slate-500 dark:text-slate-400">
                No domain maturity yet — complete assessment questions to estimate levels.
              </.p>
            <% else %>
              <div class="maturity-chart" role="img" aria-label="Domain maturity levels">
                <div :for={bar <- @maturity} class="maturity-row">
                  <span class="maturity-row__label">{bar["label"]}</span>
                  <div
                    class="maturity-row__track"
                    title={"#{bar["answered"]}/#{bar["total"]} met"}
                  >
                    <div
                      class={"maturity-row__fill maturity-row__fill--#{bar["level"]}"}
                      style={"width: #{bar["pct"]}%"}
                    >
                    </div>
                  </div>
                  <.tooltip
                    label={"#{bar["level_label"]} — #{bar["level_tip"]}"}
                    placement="top"
                  >
                    <.badge
                      color={bar["level_color"] || "primary"}
                      variant="soft"
                      label={bar["level_label"]}
                      class="maturity-row__level cursor-help"
                    />
                  </.tooltip>
                </div>
              </div>
            <% end %>
          </.card_content>
        </.card>

        <.card class="metrics-card">
          <.card_header
            title="Objective metrics"
            description="Opted-in domains from assessment wizards (finalized and in progress)."
          />
          <.card_content>
            <%= if @metrics["has_collection"] do %>
              <div class="metrics-sparklines">
                <.metric_sparkline
                  label="Yes answers"
                  suffix="%"
                  value={get_in(@metrics, ["current", "yes_pct"])}
                  series={@metrics["series"]["yes_pct"]}
                />
                <.metric_sparkline
                  label="Unanswered"
                  value={get_in(@metrics, ["current", "unanswered"])}
                  series={@metrics["series"]["unanswered"]}
                />
                <.metric_sparkline
                  label="Evidence coverage"
                  suffix="%"
                  value={get_in(@metrics, ["current", "evidence_pct"])}
                  series={@metrics["series"]["evidence_pct"]}
                />
                <.metric_sparkline
                  label="Time logged"
                  suffix="h"
                  value={get_in(@metrics, ["current", "time_hours_total"])}
                  series={@metrics["series"]["time_hours"]}
                />
              </div>

              <div
                :if={get_in(@metrics, ["current", "domains"]) not in [nil, []]}
                class="metrics-domains"
              >
                <p class="metrics-domains__title">Time by objective</p>
                <ul class="metrics-domains__list">
                  <li
                    :for={row <- get_in(@metrics, ["current", "domains"]) || []}
                    class="metrics-domains__row"
                  >
                    <span class="metrics-domains__label">{row["label"]}</span>
                    <span class="metrics-domains__scale">{row["time_scale_label"]}</span>
                    <span class="metrics-domains__hours">{format_hours(row["hours"])}</span>
                  </li>
                </ul>
              </div>
            <% else %>
              <.p no_margin class="text-base text-slate-500 dark:text-slate-400">
                Mark domains for metric collection in an assessment wizard to populate this panel.
              </.p>
            <% end %>
          </.card_content>
        </.card>
      </div>

      <%= if @assessments == [] do %>
        <.card variant="muted">
          <.card_content class="py-8 text-center">
            <.p class="text-slate-600">No assessments yet.</.p>
            <.button
              link_type="live_redirect"
              to={~p"/orgs/#{@org_id}/assessments/new"}
              label="Start an assessment"
              class="mt-2"
            />
          </.card_content>
        </.card>
      <% else %>
        <div class="space-y-8">
          <div>
            <.h3 class="mb-3">Ongoing</.h3>
            <%= if @ongoing_assessments == [] do %>
              <.p class="text-slate-500">No ongoing assessments.</.p>
            <% else %>
              <.assessment_list assessments={@ongoing_assessments} />
            <% end %>
          </div>

          <div>
            <.h3 class="mb-3">Finalized</.h3>
            <%= if @finalized_assessments == [] do %>
              <.p class="text-slate-500">No finalized assessments yet.</.p>
            <% else %>
              <.assessment_list assessments={@finalized_assessments} />
            <% end %>
          </div>
        </div>
      <% end %>
    </section>
    """
  end

  attr(:assessments, :list, required: true)

  defp assessment_list(assigns) do
    ~H"""
    <ul class="space-y-3">
      <li :for={a <- @assessments}>
        <.card class="transition hover:border-primary-300 hover:shadow-md">
          <.card_content class="flex flex-wrap items-center justify-between gap-3">
            <.link navigate={~p"/assessments/#{a["id"]}"} class="min-w-0 flex-1 no-underline">
              <span class="block font-mono text-base font-semibold text-slate-900 dark:text-slate-100">
                {a["title"]}
              </span>
            </.link>
            <.badge
              color={status_badge_color(a["status"])}
              variant="soft"
              label={status_label(a["status"])}
            />
          </.card_content>
        </.card>
      </li>
    </ul>
    """
  end

  defp format_hours(nil), do: "—"
  defp format_hours(hours) when is_number(hours), do: "#{Float.round(hours * 1.0, 1)}h"
  defp format_hours(_), do: "—"

  defp status_label(status) when status in ["complete", "archived"], do: "finalized"
  defp status_label(status) when is_binary(status) and status != "", do: status
  defp status_label(_), do: "draft"

  defp status_badge_color(status) when status in ["complete", "archived"], do: "success"
  defp status_badge_color("in_progress"), do: "primary"
  defp status_badge_color(_), do: "info"
end
