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
    <section>
      <div class="row">
        <h1>{@assessment["title"]}</h1>
        <.link navigate={~p"/assessments/#{@assessment_id}/q"} class="btn">Open wizard</.link>
      </div>
      <p class="lede">
        Status: <strong>{@assessment["status"]}</strong>
        · Kind: {@assessment["kind"]}
      </p>
      <p :if={@error} class="error" role="alert">{@error}</p>

      <div class="stack domain-manage">
        <h2 class="section-heading">Domains in this assessment</h2>
        <%= if @selected_domains == [] do %>
          <p class="empty">No domains yet.</p>
        <% else %>
          <ul class="domain-chip-list">
            <li :for={d <- @selected_domains} class="domain-chip">
              <span class="domain-chip-title">{d["label"]}</span>
              <span class="meta">{d["id"]}</span>
            </li>
          </ul>
        <% end %>

        <%= if @addable_domains != [] do %>
          <form phx-submit="add_domains" class="stack">
            <fieldset class="domain-fieldset">
              <legend>Add domains</legend>
              <div class="domain-grid">
                <label :for={domain <- @addable_domains} class="domain-option">
                  <input
                    type="checkbox"
                    name={"domains[#{domain["id"]}]"}
                    value="true"
                    class="domain-option-input"
                  />
                  <div class="domain-option-panel">
                    <span class="domain-option-title">{domain["label"]}</span>
                    <p class="domain-option-desc">{domain["description"]}</p>
                  </div>
                </label>
              </div>
            </fieldset>
            <button type="submit" class="btn">Add selected domains</button>
          </form>
        <% else %>
          <p class="empty">All available domains are already on this assessment.</p>
        <% end %>
      </div>

      <.link navigate={~p"/orgs/#{@org_id}"}>← Back to org</.link>
    </section>
    """
  end
end
