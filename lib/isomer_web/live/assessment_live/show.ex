defmodule IsomerWeb.AssessmentLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Domains
  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy
  alias Isomer.Roles

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = Tenant.canonicalize_record_id(id)

    case load_state(socket.assigns.surreal, id) do
      {:ok, state} ->
        {:ok, assign(socket, Map.put(state, :error, nil))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Assessment not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
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
                 |> assign(:error, nil)
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
            {:noreply,
             socket
             |> assign(:assessment, assessment)
             |> assign(:finalized, true)
             |> assign(:error, nil)
             |> put_flash(:info, "Assessment finalized — editing is locked.")}

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
            {:noreply,
             socket
             |> assign(:assessment, assessment)
             |> assign(:finalized, false)
             |> assign(:error, nil)
             |> put_flash(:info, "Assessment reopened for editing.")}

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
         {:ok, sets} <- Tenant.list_question_sets(surreal) do
      set_domains =
        sets
        |> Enum.map(& &1["domain"])
        |> Enum.reject(&is_nil/1)

      selected_ids = assessment["domains"] || []
      available = Domains.selectable(set_domains)
      selected = Enum.filter(available, &(&1["id"] in selected_ids))
      addable = Enum.reject(available, &(&1["id"] in selected_ids))
      role = Roles.normalize(membership["role"])

      {:ok,
       %{
         page_title: assessment["title"],
         assessment: assessment,
         assessment_id: id,
         org_id: org_id,
         selected_domains: selected,
         addable_domains: addable,
         finalized: finalized?(assessment),
         current_role: role,
         can_write: Roles.can_write?(role),
         can_delete: Roles.can_delete_assessment?(role),
         nav_org_id: org_id,
         nav_assessment_id: id,
         nav_assessment_title: assessment["title"]
       }}
    end
  end

  defp finalized?(%{"status" => status}) when status in ["complete", "archived"], do: true
  defp finalized?(_), do: false

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>{@assessment["title"]}</.h1>
          <.p class="isomer-lede flex flex-wrap items-center gap-2">
            <.badge
              color={status_badge_color(@assessment["status"])}
              variant="soft"
              label={status_label(@assessment["status"])}
            />
            <.badge color="gray" variant="soft" label={@assessment["kind"] || "domains"} />
            <.badge
              :if={classification_label(@assessment["classification"])}
              color="info"
              variant="soft"
              label={classification_label(@assessment["classification"])}
            />
          </.p>
        </div>
        <div class="flex flex-wrap gap-2">
          <.button
            link_type="live_redirect"
            to={~p"/orgs/#{@org_id}"}
            color="gray"
            variant="ghost"
            label="← Org"
            icon="hero-arrow-left"
          />
          <.button
            link_type="live_redirect"
            to={~p"/assessments/#{@assessment_id}/q"}
            label={if @finalized, do: "View wizard", else: "Open wizard"}
            icon="hero-play"
          />
          <.button
            link_type="live_redirect"
            to={~p"/assessments/#{@assessment_id}/results"}
            color="primary"
            variant="outline"
            label="Results"
            icon="hero-chart-bar"
          />
          <.button
            link_type="live_redirect"
            to={~p"/assessments/#{@assessment_id}/artifacts"}
            color="primary"
            variant="outline"
            label={GuideCopy.artifacts_nav_label()}
            icon="hero-document-text"
          />
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
            label="Delete"
            phx-click="delete"
            data-confirm={"Delete “#{@assessment["title"]}” and all its answers? This cannot be undone."}
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
        label={"Viewer access (#{Roles.label(@current_role)}) — you can browse this assessment but not edit it."}
      />

      <.alert
        :if={@finalized}
        color="warning"
        variant="soft"
        with_icon
        class="mb-4"
      >
        {GuideCopy.artifacts_finalize_hint(@guide_prefs)}
        <.link
          navigate={~p"/assessments/#{@assessment_id}/artifacts"}
          class="ml-1 font-medium underline underline-offset-2"
        >
          {GuideCopy.artifacts_nav_label()}
        </.link>
      </.alert>

      <.card :if={@assessment["ruleset_id"] not in [nil, ""]}>
        <.card_header title="Classification" />
        <.card_content class="space-y-2">
          <.p no_margin class="text-slate-700 dark:text-slate-300">
            Ruleset: <code class="text-sm">{@assessment["ruleset_id"]}</code>
          </.p>
          <.p
            :if={classification_label(@assessment["classification"])}
            no_margin
            class="text-slate-700 dark:text-slate-300"
          >
            Outcome:
            <span class="font-medium">{classification_label(@assessment["classification"])}</span>
          </.p>
          <.p
            :if={is_list(@assessment["activates"]) and @assessment["activates"] != []}
            no_margin
            class="text-slate-600 dark:text-slate-400"
          >
            {length(@assessment["activates"])} activated obligation(s). See
            <.link
              navigate={~p"/assessments/#{@assessment_id}/results"}
              class="font-medium underline underline-offset-2"
            >
              Results
            </.link>
            for residual coverage.
          </.p>
          <.p
            :if={@assessment["classification"] in [nil, %{}]}
            no_margin
            class="text-slate-500"
          >
            Answer the classification questions in the wizard to compute an outcome.
          </.p>
        </.card_content>
      </.card>

      <.card>
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
            <form phx-submit="add_domains" class="space-y-4 border-t border-slate-200 pt-4">
              <fieldset>
                <legend class="mb-2 text-base font-medium text-slate-700">Add domains</legend>
                <div class="domain-grid">
                  <label :for={domain <- @addable_domains} class="domain-option">
                    <input
                      type="checkbox"
                      name={"domains[#{domain["id"]}]"}
                      value="true"
                      class="domain-option-input"
                    />
                    <div>
                      <span class="font-semibold text-slate-900">{domain["label"]}</span>
                      <.p no_margin class="text-base text-slate-600">{domain["description"]}</.p>
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

      <.button
        link_type="live_redirect"
        to={~p"/orgs/#{@org_id}"}
        color="gray"
        variant="ghost"
        label="← Back to org"
      />
    </section>
    """
  end

  defp status_label(status) when status in ["complete", "archived"], do: "finalized"
  defp status_label(status) when is_binary(status) and status != "", do: status
  defp status_label(_), do: "draft"

  defp status_badge_color(status) when status in ["complete", "archived"], do: "success"
  defp status_badge_color("in_progress"), do: "primary"
  defp status_badge_color(_), do: "info"

  defp classification_label(%{"label" => label}) when is_binary(label) and label != "", do: label

  defp classification_label(%{"classification" => label})
       when is_binary(label) and label != "",
       do: label

  defp classification_label(_), do: nil
end
