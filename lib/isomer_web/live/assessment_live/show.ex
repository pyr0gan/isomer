defmodule IsomerWeb.AssessmentLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.AssessmentOverview
  alias Isomer.Domains
  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy
  alias Isomer.Roles

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = Tenant.canonicalize_record_id(id)

    case load_state(socket.assigns.surreal, id) do
      {:ok, state} ->
        {:ok,
         assign(
           socket,
           Map.merge(state, %{
             error: nil,
             editing_title?: false,
             title_draft: state.assessment["title"]
           })
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Assessment not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("edit_title", _params, socket) do
    if socket.assigns.can_write and not socket.assigns.finalized do
      {:noreply,
       assign(socket,
         editing_title?: true,
         title_draft: socket.assigns.assessment["title"],
         error: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_title", _params, socket) do
    {:noreply,
     assign(socket, editing_title?: false, title_draft: socket.assigns.assessment["title"])}
  end

  def handle_event("save_title", %{"title" => title}, socket) do
    cond do
      not socket.assigns.can_write ->
        {:noreply, assign(socket, error: "Viewer access — editing is not allowed.")}

      socket.assigns.finalized ->
        {:noreply, assign(socket, error: "This assessment is finalized and cannot be edited.")}

      true ->
        case Tenant.update_assessment_title(
               socket.assigns.surreal,
               socket.assigns.assessment_id,
               title
             ) do
          {:ok, assessment} ->
            {:noreply,
             socket
             |> assign(
               assessment: assessment,
               page_title: assessment["title"],
               nav_assessment_title: assessment["title"],
               editing_title?: false,
               title_draft: assessment["title"],
               error: nil
             )
             |> put_flash(:info, "Title updated")}

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end
    end
  end

  def handle_event("add_domains", params, socket) do
    cond do
      not Roles.can_write?(socket.assigns.current_role) ->
        {:noreply, assign(socket, error: "Viewer access — editing is not allowed.")}

      finalized?(socket.assigns.assessment) ->
        {:noreply, assign(socket, error: "This assessment is finalized and cannot be edited.")}

      true ->
        selected =
          params
          |> Map.get("domains", %{})
          |> Map.keys()

        case Tenant.add_assessment_domains(
               socket.assigns.surreal,
               socket.assigns.assessment_id,
               selected
             ) do
          {:ok, _assessment} ->
            case load_state(socket.assigns.surreal, socket.assigns.assessment_id) do
              {:ok, state} ->
                {:noreply,
                 socket
                 |> assign(state)
                 |> assign(
                   error: nil,
                   editing_title?: false,
                   title_draft: state.assessment["title"]
                 )
                 |> put_flash(:info, "Domains updated")}

              {:error, reason} ->
                {:noreply, assign(socket, error: format_error(reason))}
            end

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end
    end
  end

  def handle_event("finalize", _params, socket) do
    cond do
      not Roles.can_write?(socket.assigns.current_role) ->
        {:noreply, assign(socket, error: "Viewer access — editing is not allowed.")}

      finalized?(socket.assigns.assessment) ->
        {:noreply, assign(socket, error: "Already finalized.")}

      true ->
        case Tenant.update_assessment_status(
               socket.assigns.surreal,
               socket.assigns.assessment_id,
               "complete"
             ) do
          {:ok, assessment} ->
            case load_state(socket.assigns.surreal, socket.assigns.assessment_id) do
              {:ok, state} ->
                {:noreply,
                 socket
                 |> assign(state)
                 |> assign(error: nil, editing_title?: false, title_draft: assessment["title"])
                 |> put_flash(:info, "Assessment finalized — editing is locked.")}

              {:error, reason} ->
                {:noreply, assign(socket, error: format_error(reason))}
            end

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end
    end
  end

  def handle_event("reopen", _params, socket) do
    cond do
      not Roles.can_write?(socket.assigns.current_role) ->
        {:noreply, assign(socket, error: "Viewer access — editing is not allowed.")}

      finalized?(socket.assigns.assessment) ->
        case Tenant.update_assessment_status(
               socket.assigns.surreal,
               socket.assigns.assessment_id,
               "in_progress"
             ) do
          {:ok, assessment} ->
            case load_state(socket.assigns.surreal, socket.assigns.assessment_id) do
              {:ok, state} ->
                {:noreply,
                 socket
                 |> assign(state)
                 |> assign(error: nil, editing_title?: false, title_draft: assessment["title"])
                 |> put_flash(:info, "Assessment reopened for editing.")}

              {:error, reason} ->
                {:noreply, assign(socket, error: format_error(reason))}
            end

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", _params, socket) do
    if Roles.can_delete_assessment?(socket.assigns.current_role) do
      org_id = socket.assigns.org_id

      case Tenant.delete_assessment(socket.assigns.surreal, socket.assigns.assessment_id) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Assessment deleted")
           |> push_navigate(to: ~p"/orgs/#{org_id}")}

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    else
      {:noreply, assign(socket, error: "Only owners and admins can delete assessments.")}
    end
  end

  defp load_state(surreal, id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         org_id <- Tenant.canonicalize_record_id(assessment["org"]),
         {:ok, membership} <- Tenant.get_membership(surreal, org_id),
         {:ok, sets} <- Tenant.list_question_sets(surreal),
         {:ok, answers} <- Tenant.list_answers(surreal, id),
         {:ok, evidence_rows} <- Tenant.list_evidence_for_assessment(surreal, id),
         {:ok, ruleset} <- maybe_load_ruleset(surreal, assessment) do
      set_domains =
        sets
        |> Enum.map(& &1["domain"])
        |> Enum.reject(&is_nil/1)

      selected_ids = assessment["domains"] || []
      available = Domains.selectable(set_domains)
      selected = Enum.filter(available, &(&1["id"] in selected_ids))
      addable = Enum.reject(available, &(&1["id"] in selected_ids))
      role = Roles.normalize(membership["role"])

      questionnaire =
        Enum.reject(answers, fn a -> a["pack_ref"] == Tenant.artifact_pack_ref() end)

      overview =
        AssessmentOverview.build(%{
          assessment: assessment,
          question_sets: sets,
          answers: questionnaire,
          evidence_rows: evidence_rows,
          ruleset: ruleset
        })

      {:ok,
       %{
         page_title: assessment["title"],
         assessment: assessment,
         assessment_id: id,
         org_id: org_id,
         selected_domains: selected,
         addable_domains: addable,
         overview: overview,
         finalized: finalized?(assessment),
         current_role: role,
         can_write: Roles.can_write?(role),
         can_delete: Roles.can_delete_assessment?(role),
         nav_org_id: org_id,
         nav_show_members: Roles.can_manage_members?(role),
         nav_assessment_id: id,
         nav_assessment_title: assessment["title"]
       }}
    end
  end

  defp maybe_load_ruleset(_surreal, %{"ruleset_id" => id})
       when not is_binary(id) or id == "",
       do: {:ok, nil}

  defp maybe_load_ruleset(surreal, %{"ruleset_id" => id}) when is_binary(id) do
    case Tenant.get_ruleset(surreal, id) do
      {:ok, row} -> {:ok, row}
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_load_ruleset(_surreal, _), do: {:ok, nil}

  defp finalized?(%{"status" => status}) when status in ["complete", "archived"], do: true
  defp finalized?(_), do: false

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  defp format_timestamp(nil), do: nil

  defp format_timestamp(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp format_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
      _ -> value
    end
  end

  defp format_timestamp(_), do: nil

  defp primary_path(assessment_id, "wizard"), do: ~p"/assessments/#{assessment_id}/q"
  defp primary_path(assessment_id, "results"), do: ~p"/assessments/#{assessment_id}/results"
  defp primary_path(assessment_id, "artifacts"), do: ~p"/assessments/#{assessment_id}/artifacts"
  defp primary_path(assessment_id, _), do: ~p"/assessments/#{assessment_id}/q"

  defp primary_icon("results"), do: "hero-chart-bar"
  defp primary_icon("artifacts"), do: "hero-document-text"
  defp primary_icon(_), do: "hero-play"

  defp wizard_domain_path(assessment_id, domain_id) do
    ~p"/assessments/#{assessment_id}/q?domain=#{domain_id}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div class="min-w-0 flex-1">
          <%= if @editing_title? do %>
            <form phx-submit="save_title" class="assessment-hub-title-form">
              <input
                type="text"
                name="title"
                value={@title_draft}
                required
                autofocus
                class="assessment-hub-title-input"
                aria-label="Assessment title"
              />
              <div class="flex flex-wrap gap-2">
                <.button type="submit" size="sm" label="Save title" />
                <.button
                  type="button"
                  size="sm"
                  color="gray"
                  variant="ghost"
                  label="Cancel"
                  phx-click="cancel_title"
                />
              </div>
            </form>
          <% else %>
            <div class="assessment-hub-title-row">
              <.h1>{@assessment["title"]}</.h1>
              <.button
                :if={@can_write and not @finalized}
                type="button"
                size="sm"
                color="gray"
                variant="ghost"
                label="Rename"
                phx-click="edit_title"
              />
            </div>
          <% end %>
          <.p class="isomer-lede flex flex-wrap items-center gap-2">
            <.badge
              color={status_badge_color(@assessment["status"])}
              variant="soft"
              label={status_label(@assessment["status"])}
            />
            <span :if={format_timestamp(@assessment["updated_at"])} class="text-slate-500">
              Updated {format_timestamp(@assessment["updated_at"])}
            </span>
            <span :if={format_timestamp(@assessment["created_at"])} class="text-slate-400">
              · Created {format_timestamp(@assessment["created_at"])}
            </span>
          </.p>
          <.p
            :if={@overview["classification_label"] || @overview["has_ruleset"]}
            class="text-slate-600 dark:text-slate-400"
          >
            <%= if @overview["classification_label"] do %>
              Classification: <span class="font-medium">{@overview["classification_label"]}</span>
              <%= if @overview["activates_count"] > 0 do %>
                · {@overview["activates_count"]} obligation(s)
              <% end %>
              —
              <.link
                navigate={~p"/assessments/#{@assessment_id}/results"}
                class="font-medium underline underline-offset-2"
              >
                Results
              </.link>
            <% else %>
              Ruleset linked — answer classification in the questionnaire to compute an outcome.
            <% end %>
          </.p>
        </div>
        <div class="flex flex-wrap gap-2">
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

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} class="mb-4" />

      <.alert
        :if={not @can_write}
        color="info"
        variant="soft"
        with_icon
        class="mb-4"
        label={"Viewer access (#{Roles.label(@current_role)}) — you can browse this assessment but not edit it."}
      />

      <.card class="mb-6 assessment-hub-cta-card">
        <.card_content class="flex flex-wrap items-center justify-between gap-4">
          <div class="min-w-0 space-y-1">
            <.p no_margin class="text-base font-medium text-slate-800 dark:text-slate-100">
              {@overview["primary_action"]["hint"]}
            </.p>
            <.p no_margin class="text-sm text-slate-500">
              {@overview["answered"]}/{@overview["total"]} answered
              <%= if @overview["unanswered"] > 0 do %>
                · {@overview["unanswered"]} open
              <% end %>
              <%= if @overview["evidence_pct"] do %>
                · {@overview["evidence_pct"]}% evidence coverage
              <% end %>
            </.p>
          </div>
          <.button
            link_type="live_redirect"
            to={primary_path(@assessment_id, @overview["primary_action"]["kind"])}
            label={@overview["primary_action"]["label"]}
            icon={primary_icon(@overview["primary_action"]["kind"])}
          />
        </.card_content>
      </.card>

      <.card class="mb-6">
        <.card_header
          title="Progress"
          description="Domain (and classification) completion for this run."
        />
        <.card_content>
          <%= if @overview["sections"] == [] do %>
            <.p no_margin class="text-slate-500">
              No domains or classification questions yet.
              <%= if @can_write and not @finalized do %>
                Add domains below or open the questionnaire.
              <% end %>
            </.p>
          <% else %>
            <ul class="assessment-hub-sections">
              <li :for={section <- @overview["sections"]} class="assessment-hub-section">
                <div class="assessment-hub-section__main">
                  <.link
                    navigate={wizard_domain_path(@assessment_id, section["id"])}
                    class="assessment-hub-section__label"
                  >
                    {section["label"]}
                  </.link>
                  <span class="assessment-hub-section__counts">
                    {section["answered"]}/{section["total"]}
                    <span :if={section["unanswered"] > 0} class="text-slate-400">
                      ({section["unanswered"]} open)
                    </span>
                  </span>
                </div>
                <div
                  class="assessment-hub-section__track"
                  aria-hidden="true"
                  title={"#{section["answered"]} of #{section["total"]} answered"}
                >
                  <div
                    class="assessment-hub-section__fill"
                    style={"width: #{section_pct(section)}%"}
                  >
                  </div>
                </div>
              </li>
            </ul>
          <% end %>
        </.card_content>
      </.card>

      <.card class="mb-6">
        <.card_header title="Domains in this assessment" />
        <.card_content class="space-y-4">
          <%= if @selected_domains == [] do %>
            <.p class="text-slate-600">No domains yet.</.p>
          <% else %>
            <ul class="flex flex-wrap gap-2">
              <li :for={d <- @selected_domains}>
                <.badge color="primary" variant="soft" label={d["label"]} />
              </li>
            </ul>
          <% end %>

          <%= if @can_write and not @finalized and @addable_domains != [] do %>
            <form phx-submit="add_domains" class="space-y-4 border-t border-slate-200 pt-4 dark:border-slate-700">
              <fieldset>
                <legend class="mb-2 text-base font-medium text-slate-700 dark:text-slate-300">
                  Add domains
                </legend>
                <div class="domain-grid">
                  <label :for={domain <- @addable_domains} class="domain-option">
                    <input
                      type="checkbox"
                      name={"domains[#{domain["id"]}]"}
                      value="true"
                      class="domain-option-input"
                    />
                    <div>
                      <span class="font-semibold text-slate-900 dark:text-slate-100">
                        {domain["label"]}
                      </span>
                      <.p no_margin class="text-base text-slate-600 dark:text-slate-400">
                        {domain["description"]}
                      </.p>
                    </div>
                  </label>
                </div>
              </fieldset>
              <.button type="submit" label="Add selected domains" size="sm" />
            </form>
          <% else %>
            <.p :if={@can_write and not @finalized} class="text-slate-500">
              All available domains are already on this assessment.
            </.p>
          <% end %>
        </.card_content>
      </.card>

      <.card class="mb-6">
        <.card_header
          title="Lifecycle"
          description="Finalize locks wizard edits. Reopen if something needs changing. Delete removes answers and evidence."
        />
        <.card_content class="flex flex-wrap gap-2">
          <%= if @can_write do %>
            <%= if @finalized do %>
              <.button
                type="button"
                color="gray"
                variant="outline"
                label="Reopen"
                phx-click="reopen"
                data-confirm="Reopen this assessment for editing?"
              />
            <% else %>
              <.button
                type="button"
                color="success"
                variant="outline"
                label="Finalize"
                phx-click="finalize"
                data-confirm="Finalize this assessment? Editing will be locked until you reopen it."
              />
            <% end %>
          <% end %>
          <.button
            :if={@can_delete}
            type="button"
            color="danger"
            variant="outline"
            label="Delete assessment"
            phx-click="delete"
            data-confirm={"Delete “#{@assessment["title"]}” and all its answers? This cannot be undone."}
          />
          <.p
            :if={not @can_write and not @can_delete}
            no_margin
            class="text-sm text-slate-500"
          >
            Only writers can finalize or reopen; only owners and admins can delete.
          </.p>
        </.card_content>
      </.card>

      <div class="flex flex-wrap gap-2">
        <.button
          link_type="live_redirect"
          to={~p"/assessments/#{@assessment_id}/q"}
          color="gray"
          variant="outline"
          label={if @finalized, do: "View wizard", else: "Open wizard"}
          icon="hero-play"
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
          to={~p"/assessments/#{@assessment_id}/artifacts"}
          color="gray"
          variant="outline"
          label={GuideCopy.artifacts_nav_label()}
          icon="hero-document-text"
        />
      </div>
    </section>
    """
  end

  defp section_pct(%{"total" => total}) when total in [0, nil], do: 0

  defp section_pct(%{"answered" => answered, "total" => total})
       when is_number(answered) and is_number(total) and total > 0 do
    round(100 * answered / total)
  end

  defp section_pct(_), do: 0

  defp status_label(status) when status in ["complete", "archived"], do: "finalized"
  defp status_label(status) when is_binary(status) and status != "", do: status
  defp status_label(_), do: "draft"

  defp status_badge_color(status) when status in ["complete", "archived"], do: "success"
  defp status_badge_color("in_progress"), do: "primary"
  defp status_badge_color(_), do: "info"
end
