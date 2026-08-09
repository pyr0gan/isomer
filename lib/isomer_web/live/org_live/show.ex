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
    <section>
      <div class="row">
        <div>
          <h1>{@org["name"]}</h1>
          <p class="meta">id …{Tenant.short_key(@org_id)}</p>
        </div>
        <div class="row">
          <.link navigate={~p"/orgs/#{@org_id}/assessments/new"} class="btn">New assessment</.link>
          <button
            type="button"
            class="btn btn-danger"
            phx-click="delete"
            data-confirm={"Delete “#{@org["name"]}” and all its assessments? This cannot be undone."}
          >
            Delete org
          </button>
        </div>
      </div>
      <p class="lede">Assessments for this tenant.</p>
      <p :if={@error} class="error" role="alert">{@error}</p>

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
