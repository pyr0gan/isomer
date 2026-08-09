defmodule IsomerWeb.OrgLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    org_id = Tenant.canonicalize_record_id(org_id)

    with {:ok, org} <- Tenant.get_org(socket.assigns.surreal, org_id),
         {:ok, assessments} <- Tenant.list_assessments(socket.assigns.surreal, org_id) do
      {:ok,
       assign(socket,
         page_title: org["name"],
         org: org,
         org_id: org_id,
         assessments: assessments,
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
    <section class="space-y-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <.h1>{@org["name"]}</.h1>
          <.p class="text-slate-500">id …{Tenant.short_key(@org_id)}</.p>
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

      <.p class="text-slate-600">Assessments for this tenant.</.p>
      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <%= if @assessments == [] do %>
        <.card variant="muted">
          <.card_content>
            <.p no_margin class="text-slate-600">No assessments yet.</.p>
          </.card_content>
        </.card>
      <% else %>
        <ul class="space-y-3">
          <li :for={a <- @assessments}>
            <.card>
              <.card_content>
                <.link navigate={~p"/assessments/#{a["id"]}"} class="no-underline">
                  <span class="font-semibold text-slate-900">{a["title"]}</span>
                  <.badge color="gray" label={a["status"]} class="ml-2" />
                </.link>
              </.card_content>
            </.card>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end
end
