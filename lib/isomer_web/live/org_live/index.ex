defmodule IsomerWeb.OrgLive.Index do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(_params, _session, socket) do
    orgs =
      case Tenant.list_orgs(socket.assigns.surreal) do
        {:ok, rows} -> rows
        {:error, _} -> []
      end

    {:ok, assign(socket, page_title: "Organizations", orgs: orgs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <div class="row">
        <h1>Organizations</h1>
        <.link navigate={~p"/orgs/new"} class="btn">New org</.link>
      </div>
      <p class="lede">Tenants you belong to via Surreal `member` edges.</p>

      <%= if @orgs == [] do %>
        <p class="empty">No organizations yet. Create one to start an assessment.</p>
      <% else %>
        <ul class="list">
          <li :for={org <- @orgs}>
            <.link navigate={~p"/orgs/#{org["id"]}"}>{org["name"]}</.link>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end
end
