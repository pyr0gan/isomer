defmodule IsomerWeb.OrgLive.New do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "New organization", name: "", error: nil)}
  end

  @impl true
  def handle_event("save", %{"name" => name}, socket) do
    case Tenant.create_org(socket.assigns.surreal, name) do
      {:ok, org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created")
         |> push_navigate(to: ~p"/orgs/#{org["id"]}")}

      {:error, reason} ->
        {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>New organization</h1>
      <p class="lede">Creates an `org` and relates you as `owner`.</p>
      <p :if={@error} class="error" role="alert">{@error}</p>
      <form phx-submit="save" class="stack">
        <label>
          Name
          <input type="text" name="name" value={@name} required autofocus />
        </label>
        <div class="row">
          <button type="submit" class="btn">Create</button>
          <.link navigate={~p"/orgs"} class="btn btn-quiet">Cancel</.link>
        </div>
      </form>
    </section>
    """
  end
end
