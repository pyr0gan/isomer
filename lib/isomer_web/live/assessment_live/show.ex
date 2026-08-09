defmodule IsomerWeb.AssessmentLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Domains
  alias Isomer.Db.Tenant

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

  defp load_state(surreal, id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         {:ok, sets} <- Tenant.list_question_sets(surreal) do
      set_domains =
        sets
        |> Enum.map(& &1["domain"])
        |> Enum.reject(&is_nil/1)

      selected_ids = assessment["domains"] || []
      available = Domains.selectable(set_domains)
      selected = Enum.filter(available, &(&1["id"] in selected_ids))
      addable = Enum.reject(available, &(&1["id"] in selected_ids))

      {:ok,
       %{
         page_title: assessment["title"],
         assessment: assessment,
         assessment_id: id,
         org_id: Tenant.canonicalize_record_id(assessment["org"]),
         selected_domains: selected,
         addable_domains: addable
       }}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="space-y-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <.h1>{@assessment["title"]}</.h1>
          <.p class="text-slate-600">
            Status: <.badge color="info" label={@assessment["status"]} />
            · Kind: {@assessment["kind"]}
          </.p>
        </div>
        <.button
          link_type="live_redirect"
          to={~p"/assessments/#{@assessment_id}/q"}
          label="Open wizard"
          icon="hero-play"
        />
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

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

          <%= if @addable_domains != [] do %>
            <form phx-submit="add_domains" class="space-y-4 border-t border-slate-200 pt-4">
              <fieldset>
                <legend class="mb-2 text-sm font-medium text-slate-700">Add domains</legend>
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
                      <.p no_margin class="text-sm text-slate-600">{domain["description"]}</.p>
                    </div>
                  </label>
                </div>
              </fieldset>
              <.button type="submit" label="Add selected domains" size="sm" />
            </form>
          <% else %>
            <.p class="text-slate-500">All available domains are already on this assessment.</.p>
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
end
