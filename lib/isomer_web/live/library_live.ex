defmodule IsomerWeb.LibraryLive do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy

  @impl true
  def mount(_params, _session, socket) do
    case load(socket.assigns.surreal) do
      {:ok, templates, artifacts} ->
        {:ok,
         assign(socket,
           page_title: "Library",
           templates: templates,
           artifacts: artifacts,
           error: nil
         )}

      {:error, reason} ->
        {:ok,
         assign(socket,
           page_title: "Library",
           templates: [],
           artifacts: [],
           error: format_error(reason)
         )}
    end
  end

  @impl true
  def handle_event("delete_artifact", %{"id" => id}, socket) do
    case Tenant.delete_artifact(socket.assigns.surreal, id) do
      :ok ->
        case load(socket.assigns.surreal) do
          {:ok, templates, artifacts} ->
            {:noreply,
             socket
             |> assign(templates: templates, artifacts: artifacts, error: nil)
             |> put_flash(:info, "Artifact deleted")}

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp load(surreal) do
    with {:ok, templates} <- Tenant.list_templates(surreal),
         {:ok, artifacts} <- Tenant.list_artifacts(surreal) do
      {:ok, templates, artifacts}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  defp covers_count(%{"covers" => covers}) when is_list(covers), do: length(covers)
  defp covers_count(_), do: 0

  defp merge_count(%{"merge_fields" => fields}) when is_list(fields), do: length(fields)
  defp merge_count(_), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>Library</.h1>
          <.p class="isomer-lede">{GuideCopy.library_intro(@guide_prefs)}</.p>
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <div class="isomer-library">
        <section class="isomer-library__section">
          <h2 class="isomer-library__heading">Templates</h2>
          <.p class="text-base text-slate-600 dark:text-slate-400">
            Published from the corpus. Generate a filled draft from any assessment’s Artifacts page.
          </.p>

          <%= if @templates == [] do %>
            <.p class="text-slate-500">No templates synced yet.</.p>
          <% else %>
            <ul class="isomer-library__list">
              <li :for={tmpl <- @templates} class="isomer-library__row">
                <div>
                  <p class="isomer-library__title">{tmpl["name"]}</p>
                  <p class="isomer-library__meta">
                    {tmpl["corpus_id"]} · v{tmpl["version"] || "—"} · {covers_count(tmpl)} requirements · {merge_count(
                      tmpl
                    )} fields
                  </p>
                </div>
              </li>
            </ul>
          <% end %>
        </section>

        <section class="isomer-library__section">
          <h2 class="isomer-library__heading">Generated artifacts</h2>
          <.p class="text-base text-slate-600 dark:text-slate-400">
            Drafts stored for your organizations. Open an assessment to create new ones.
          </.p>

          <%= if @artifacts == [] do %>
            <.p class="text-slate-500">No artifacts yet — open an assessment and choose Artifacts from the menu.</.p>
          <% else %>
            <ul class="isomer-library__list">
              <li :for={art <- @artifacts} class="isomer-library__row">
                <div class="min-w-0 flex-1">
                  <p class="isomer-library__title">{art["title"]}</p>
                  <p class="isomer-library__meta">
                    {art["template_id"]} · {art["id"]}
                  </p>
                </div>
                <div class="isomer-library__actions">
                  <.button
                    link_type="a"
                    to={~p"/artifacts/#{art["id"]}/download?format=markdown"}
                    color="gray"
                    variant="outline"
                    size="sm"
                    label="Markdown"
                  />
                  <.button
                    link_type="a"
                    to={~p"/artifacts/#{art["id"]}/download?format=pdf"}
                    color="gray"
                    variant="outline"
                    size="sm"
                    label="PDF"
                  />
                  <.button
                    :if={art["assessment"]}
                    link_type="live_redirect"
                    to={~p"/assessments/#{Tenant.canonicalize_record_id(art["assessment"])}/artifacts"}
                    color="gray"
                    variant="ghost"
                    size="sm"
                    label="Open"
                  />
                  <.button
                    type="button"
                    color="danger"
                    variant="ghost"
                    size="sm"
                    label="Delete"
                    phx-click="delete_artifact"
                    phx-value-id={art["id"]}
                    data-confirm="Delete this artifact?"
                  />
                </div>
              </li>
            </ul>
          <% end %>
        </section>
      </div>
    </section>
    """
  end
end
