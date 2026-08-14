defmodule IsomerWeb.AssessmentLive.Artifacts do
  use IsomerWeb.SurrealLive

  alias Isomer.Artifacts.Render
  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy
  alias Isomer.Roles

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = Tenant.canonicalize_record_id(id)

    case load_state(socket.assigns.surreal, id) do
      {:ok, state} ->
        {:ok,
         socket
         |> assign(state)
         |> assign(
           error: nil,
           selected_template_id: nil,
           merge_form: %{},
           preview_fields: []
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Assessment not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("select_template", %{"template_id" => template_id}, socket) do
    template_id = template_id |> to_string() |> String.trim()

    if template_id == "" do
      {:noreply,
       assign(socket,
         selected_template_id: nil,
         preview_fields: [],
         merge_form: %{},
         error: nil
       )}
    else
      case Enum.find(socket.assigns.templates, &(&1["corpus_id"] == template_id)) do
        nil ->
          {:noreply, assign(socket, error: "Template not found", selected_template_id: nil)}

        tmpl ->
          fields = tmpl["merge_fields"] || Render.extract_fields(tmpl["body"] || "")
          values = Render.build_values(socket.assigns.org, socket.assigns.assessment, %{})

          merge_form =
            Map.new(fields, fn field ->
              {field, Map.get(values, field, "")}
            end)

          {:noreply,
           assign(socket,
             selected_template_id: template_id,
             preview_fields: fields,
             merge_form: merge_form,
             error: nil
           )}
      end
    end
  end

  def handle_event("generate", params, socket) do
    if not socket.assigns.can_write do
      {:noreply, assign(socket, error: "Viewer access — you cannot generate documents.")}
    else
      template_id = Map.get(params, "template_id") || socket.assigns.selected_template_id

      case Enum.find(socket.assigns.templates, &(&1["corpus_id"] == template_id)) do
        nil ->
          {:noreply, assign(socket, error: "Choose a template first.")}

        tmpl ->
          fields = tmpl["merge_fields"] || []
          overrides = Map.get(params, "merge", %{})

          values =
            Render.build_values(socket.assigns.org, socket.assigns.assessment, overrides)

          # Keep only declared fields (+ anything typed) for storage clarity
          stored =
            fields
            |> Enum.map(fn f -> {f, Map.get(values, f, Map.get(overrides, f, ""))} end)
            |> Map.new()

          body = Render.render(tmpl["body"] || "", Map.merge(values, stored))
          title = "#{tmpl["name"]} — #{socket.assigns.org["name"]}"

          attrs = %{
            "org_id" => socket.assigns.org_id,
            "assessment_id" => socket.assigns.assessment_id,
            "template_id" => tmpl["corpus_id"],
            "title" => title,
            "body" => body,
            "merge_values" => stored
          }

          case Tenant.create_artifact(socket.assigns.surreal, attrs) do
            {:ok, _artifact} ->
              case load_state(socket.assigns.surreal, socket.assigns.assessment_id) do
                {:ok, state} ->
                  {:noreply,
                   socket
                   |> assign(state)
                   |> assign(
                     error: nil,
                     selected_template_id: template_id,
                     preview_fields: fields,
                     merge_form: stored
                   )
                   |> put_flash(:info, "Artifact generated")}

                {:error, reason} ->
                  {:noreply, assign(socket, error: format_error(reason))}
              end

            {:error, reason} ->
              {:noreply, assign(socket, error: format_error(reason))}
          end
      end
    end
  end

  def handle_event("delete_artifact", %{"id" => id}, socket) do
    if not socket.assigns.can_write do
      {:noreply, assign(socket, error: "Viewer access — you cannot delete documents.")}
    else
      case Tenant.delete_artifact(socket.assigns.surreal, id) do
        :ok ->
          case load_state(socket.assigns.surreal, socket.assigns.assessment_id) do
            {:ok, state} ->
              {:noreply,
               socket
               |> assign(state)
               |> assign(:error, nil)
               |> put_flash(:info, "Artifact deleted")}

            {:error, reason} ->
              {:noreply, assign(socket, error: format_error(reason))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    end
  end

  defp load_state(surreal, assessment_id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, assessment_id),
         org_id <- Tenant.canonicalize_record_id(assessment["org"]),
         {:ok, org} <- Tenant.get_org(surreal, org_id),
         {:ok, templates} <- Tenant.list_templates(surreal),
         {:ok, artifacts} <- Tenant.list_artifacts_for_assessment(surreal, assessment_id) do
      {role, can_write} =
        case Tenant.get_membership(surreal, org_id) do
          {:ok, membership} ->
            r = Roles.normalize(membership["role"])
            {r, Roles.can_write?(r)}

          {:error, _} ->
            {"viewer", false}
        end

      {:ok,
       %{
         page_title: "Generate documents · #{assessment["title"]}",
         assessment: assessment,
         assessment_id: assessment_id,
         org: org,
         org_id: org_id,
         templates: templates,
         artifacts: artifacts,
         current_role: role,
         can_write: can_write,
         nav_org_id: org_id,
         nav_assessment_id: assessment_id,
         nav_assessment_title: assessment["title"]
       }}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  defp selected_template(assigns) do
    Enum.find(assigns.templates, &(&1["corpus_id"] == assigns.selected_template_id))
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :selected, selected_template(assigns))

    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>Generate documents</.h1>
          <.p class="isomer-lede">
            {@assessment["title"]} — {GuideCopy.artifacts_intro(@guide_prefs)}
          </.p>
        </div>
        <div class="flex flex-wrap gap-2">
          <.button
            link_type="live_redirect"
            to={~p"/assessments/#{@assessment_id}"}
            color="gray"
            variant="outline"
            label="Details"
            icon="hero-information-circle"
          />
          <.button
            link_type="live_redirect"
            to={~p"/assessments/#{@assessment_id}/q"}
            color="gray"
            variant="outline"
            label="Questionnaire"
            icon="hero-queue-list"
          />
          <.button
            link_type="live_redirect"
            to={~p"/assessments/#{@assessment_id}/results"}
            color="gray"
            variant="outline"
            label="Results"
            icon="hero-chart-bar"
          />
          <.button
            link_type="live_redirect"
            to={~p"/orgs/#{@org_id}"}
            color="gray"
            variant="ghost"
            label="Org"
            icon="hero-arrow-left"
          />
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <.alert
        :if={not @can_write}
        color="info"
        variant="soft"
        with_icon
        class="mb-4"
        label={"Viewer access (#{Roles.label(@current_role)}) — you can download drafts but not generate new ones."}
      />

      <section class="isomer-library__section">
        <h2 class="isomer-library__heading">Generate from a template</h2>

        <%= if not @can_write do %>
          <.p class="text-slate-500">Document generation requires assessor access or higher.</.p>
        <% else %>
          <%= if @templates == [] do %>
            <.p class="text-slate-500">
              No templates available. Sync the corpus, then re-run <code>mix isomer.db.ensure_runtime</code>.
            </.p>
          <% else %>
            <form phx-change="select_template" class="mb-4">
              <label class="isomer-settings__label" for="template_id">Template</label>
              <select
                id="template_id"
                name="template_id"
                class="wizard-domain-time__control max-w-lg"
              >
                {Phoenix.HTML.Form.options_for_select(
                  [{"Choose a template…", ""} | Enum.map(@templates, &{&1["name"], &1["corpus_id"]})],
                  @selected_template_id || ""
                )}
              </select>
            </form>

            <%= if @selected do %>
              <form phx-submit="generate" class="space-y-4">
                <input type="hidden" name="template_id" value={@selected["corpus_id"]} />
                <.p class="text-base text-slate-600 dark:text-slate-400">
                  Covers {length(@selected["covers"] || [])} requirement(s). Fill what you know — blanks become “—” in the draft.
                </.p>

                <div :if={@preview_fields != []} class="isomer-settings__fields">
                  <div :for={field <- @preview_fields} class="isomer-settings__field">
                    <label class="isomer-settings__label" for={"merge-#{field}"}>{field}</label>
                    <input
                      id={"merge-#{field}"}
                      type="text"
                      name={"merge[#{field}]"}
                      value={Map.get(@merge_form, field, "")}
                      class="wizard-domain-time__control"
                      placeholder={GuideCopy.merge_field_hint(@guide_prefs, field)}
                    />
                    <.p
                      :if={GuideCopy.guided?(@guide_prefs)}
                      no_margin
                      class="text-sm text-slate-500"
                    >
                      {GuideCopy.merge_field_hint(@guide_prefs, field)}
                    </.p>
                  </div>
                </div>

                <.button type="submit" label="Generate draft" icon="hero-document-plus" />
              </form>
            <% end %>
          <% end %>
        <% end %>
      </section>

      <section class="isomer-library__section">
        <h2 class="isomer-library__heading">Generated for this assessment</h2>

        <%= if @artifacts == [] do %>
          <.p class="text-slate-500">No artifacts yet for this assessment.</.p>
        <% else %>
          <ul class="isomer-library__list">
            <li :for={art <- @artifacts} class="isomer-library__row isomer-library__row--stack">
              <div class="isomer-library__row-top">
                <div class="min-w-0 flex-1">
                  <p class="isomer-library__title">{art["title"]}</p>
                  <p class="isomer-library__meta">{art["template_id"]}</p>
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
              </div>
              <details class="isomer-artifact-preview">
                <summary>Preview</summary>
                <pre class="isomer-artifact-preview__body">{art["body"]}</pre>
              </details>
            </li>
          </ul>
        <% end %>
      </section>
    </section>
    """
  end
end
