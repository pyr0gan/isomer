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
    <section class="isomer-page mx-auto max-w-lg">
      <.h1>New organization</.h1>
      <.p class="isomer-lede">Creates an `org` and relates you as `owner`.</.p>
      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <.card>
        <.card_content>
          <form phx-submit="save" class="space-y-4">
            <.field type="text" name="name" label="Name" value={@name} required autofocus />
            <div class="flex flex-wrap gap-2">
              <.button type="submit" label="Create" />
              <.button
                link_type="live_redirect"
                to={~p"/orgs"}
                color="gray"
                variant="ghost"
                label="Cancel"
              />
            </div>
          </form>
        </.card_content>
      </.card>
    </section>
    """
  end
end
