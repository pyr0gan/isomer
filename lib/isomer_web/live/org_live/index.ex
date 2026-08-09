defmodule IsomerWeb.OrgLive.Index do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Organizations", orgs: load_orgs(socket), error: nil)}
  end

  @impl true
  def handle_event("delete", %{"id" => org_id}, socket) do
    case Tenant.delete_org(socket.assigns.surreal, org_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization deleted")
         |> assign(orgs: load_orgs(socket), error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp load_orgs(socket) do
    case Tenant.list_orgs(socket.assigns.surreal) do
      {:ok, rows} -> rows
      {:error, _} -> []
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <div class="row">
        <h1>Organizations</h1>
        <.link navigate={~p"/orgs/new"} class="btn">New org</.link>
      </div>
      <p class="lede">Tenants you belong to via Surreal `member` edges.</p>
      <p :if={@error} class="error" role="alert">{@error}</p>

      <%= if @orgs == [] do %>
        <p class="empty">No organizations yet. Create one to start an assessment.</p>
      <% else %>
        <ul class="list org-list">
          <li :for={org <- @orgs} class="org-row">
            <.link navigate={~p"/orgs/#{org["id"]}"} class="org-link">
              <span class="org-name">{org["name"]}</span>
              <span class="meta">id …{Tenant.short_key(org["id"])}</span>
            </.link>
            <button
              type="button"
              class="btn btn-danger btn-small"
              phx-click="delete"
              phx-value-id={org["id"]}
              data-confirm={"Delete “#{org["name"]}” (…#{Tenant.short_key(org["id"])}) and all its assessments?"}
            >
              Delete
            </button>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end
end
