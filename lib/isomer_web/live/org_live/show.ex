defmodule IsomerWeb.OrgLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant
  alias Isomer.Maturity

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

      {:ok,
       assign(socket,
         page_title: org["name"],
         org: org,
         org_id: org_id,
         assessments: assessments,
         maturity: maturity,
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

      <.card :if={@maturity != []} class="maturity-card">
        <.card_header
          title="Org maturity"
          description="Estimated from Yes answers on L1/L2 questions (newest assessment wins)."
        />
        <.card_content>
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
                placement="left"
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
        </.card_content>
      </.card>

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
        <ul class="space-y-3">
          <li :for={a <- @assessments}>
            <.card class="transition hover:border-primary-300 hover:shadow-md">
              <.card_content class="flex flex-wrap items-center justify-between gap-3">
                <.link navigate={~p"/assessments/#{a["id"]}"} class="min-w-0 flex-1 no-underline">
                  <span class="block font-mono text-base font-semibold text-slate-900 dark:text-slate-100">
                    {a["title"]}
                  </span>
                </.link>
                <.badge color="info" variant="soft" label={a["status"] || "draft"} />
              </.card_content>
            </.card>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end
end
