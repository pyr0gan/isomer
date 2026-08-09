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
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>Organizations</.h1>
          <.p class="isomer-lede">
            Tenants you belong to. Create one to start a maturity assessment.
          </.p>
        </div>
        <.button
          link_type="live_redirect"
          to={~p"/orgs/new"}
          label="New org"
          icon="hero-plus"
        />
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <%= if @orgs == [] do %>
        <.card variant="muted">
          <.card_content class="py-8 text-center">
            <.p class="text-slate-600">No organizations yet.</.p>
            <.button
              link_type="live_redirect"
              to={~p"/orgs/new"}
              label="Create your first org"
              class="mt-2"
            />
          </.card_content>
        </.card>
      <% else %>
        <ul class="space-y-3">
          <li :for={org <- @orgs}>
            <.card class="transition hover:border-primary-300 hover:shadow-md">
              <.card_content class="flex flex-wrap items-center justify-between gap-3">
                <.link navigate={~p"/orgs/#{org["id"]}"} class="min-w-0 flex-1 no-underline">
                  <span class="block text-lg font-semibold text-slate-900 dark:text-slate-100">
                    {org["name"]}
                  </span>
                  <span class="text-sm text-slate-500 dark:text-slate-400">
                    id …{Tenant.short_key(org["id"])}
                  </span>
                </.link>
                <.button
                  type="button"
                  color="danger"
                  variant="ghost"
                  size="sm"
                  label="Delete"
                  icon="hero-trash"
                  phx-click="delete"
                  phx-value-id={org["id"]}
                  data-confirm={"Delete “#{org["name"]}” (…#{Tenant.short_key(org["id"])}) and all its assessments?"}
                />
              </.card_content>
            </.card>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end
end
