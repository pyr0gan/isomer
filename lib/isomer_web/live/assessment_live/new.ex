defmodule IsomerWeb.AssessmentLive.New do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    org_id = Tenant.canonicalize_record_id(org_id)

    sets =
      case Tenant.list_question_sets(socket.assigns.surreal) do
        {:ok, rows} -> rows
        {:error, _} -> []
      end

    domains =
      sets
      |> Enum.map(& &1["domain"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok,
     assign(socket,
       page_title: "New assessment",
       org_id: org_id,
       title: "",
       domains: domains,
       selected_domains: [],
       error: nil
     )}
  end

  @impl true
  def handle_event("save", params, socket) do
    selected =
      params
      |> Map.get("domains", %{})
      |> Map.keys()

    attrs = %{
      "title" => params["title"] || "Assessment",
      "kind" => "domains",
      "domains" => selected,
      "ruleset_id" => nil
    }

    case Tenant.create_assessment(socket.assigns.surreal, socket.assigns.org_id, attrs) do
      {:ok, assessment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Assessment created")
         |> push_navigate(to: ~p"/assessments/#{assessment["id"]}/q")}

      {:error, reason} ->
        {:noreply, assign(socket, error: inspect(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>New assessment</h1>
      <p class="lede">Pick one or more question-set domains from the published corpus.</p>
      <p :if={@error} class="error" role="alert">{@error}</p>

      <form phx-submit="save" class="stack">
        <label>
          Title
          <input type="text" name="title" value={@title} required autofocus />
        </label>

        <fieldset>
          <legend>Domains</legend>
          <%= if @domains == [] do %>
            <p class="empty">
              No question sets visible. Run <code>mix isomer.db.sync</code> then
              <code>mix isomer.db.ensure_runtime</code>.
            </p>
          <% else %>
            <label :for={domain <- @domains} class="check">
              <input type="checkbox" name={"domains[#{domain}]"} value="true" />
              {domain}
            </label>
          <% end %>
        </fieldset>

        <div class="row">
          <button type="submit" class="btn" disabled={@domains == []}>Create & open wizard</button>
          <.link navigate={~p"/orgs/#{@org_id}"} class="btn btn-quiet">Cancel</.link>
        </div>
      </form>
    </section>
    """
  end
end
