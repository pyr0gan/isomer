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
         assessments: assessments
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
  def render(assigns) do
    ~H"""
    <section>
      <div class="row">
        <h1>{@org["name"]}</h1>
        <.link navigate={~p"/orgs/#{@org_id}/assessments/new"} class="btn">New assessment</.link>
      </div>
      <p class="lede">Assessments for this tenant.</p>

      <%= if @assessments == [] do %>
        <p class="empty">No assessments yet.</p>
      <% else %>
        <ul class="list">
          <li :for={a <- @assessments}>
            <.link navigate={~p"/assessments/#{a["id"]}"}>
              {a["title"]} <span class="meta">{a["status"]}</span>
            </.link>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end
end
