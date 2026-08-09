defmodule IsomerWeb.AssessmentLive.New do
  use IsomerWeb.SurrealLive

  alias Isomer.Domains
  alias Isomer.Db.Tenant
  alias Isomer.Namegen

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    org_id = Tenant.canonicalize_record_id(org_id)

    set_domains =
      case Tenant.list_question_sets(socket.assigns.surreal) do
        {:ok, rows} ->
          rows
          |> Enum.map(& &1["domain"])
          |> Enum.reject(&is_nil/1)

        {:error, _} ->
          []
      end

    domains = Domains.selectable(set_domains)
    title = Namegen.generate()

    {:ok,
     assign(socket,
       page_title: "New assessment",
       org_id: org_id,
       title: title,
       edit_title?: false,
       domains: domains,
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_edit_title", _params, socket) do
    edit? = !socket.assigns.edit_title?

    socket =
      if edit? do
        assign(socket, edit_title?: true)
      else
        # Turning edit off restores / keeps a generated-style title.
        title =
          if Namegen.valid?(socket.assigns.title) do
            socket.assigns.title
          else
            Namegen.generate()
          end

        assign(socket, edit_title?: false, title: title)
      end

    {:noreply, socket}
  end

  def handle_event("regenerate_title", _params, socket) do
    {:noreply, assign(socket, title: Namegen.generate())}
  end

  def handle_event("title_change", %{"title" => title}, socket) do
    {:noreply, assign(socket, title: title)}
  end

  def handle_event("save", params, socket) do
    selected =
      params
      |> Map.get("domains", %{})
      |> Map.keys()

    title =
      cond do
        socket.assigns.edit_title? ->
          params["title"] |> to_string() |> String.trim()

        true ->
          socket.assigns.title
      end

    title = if title == "", do: Namegen.generate(), else: title

    attrs = %{
      "title" => title,
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
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h1>New assessment</h1>
      <p class="lede">Pick one or more question-set domains from the published corpus.</p>
      <p :if={@error} class="error" role="alert">{@error}</p>

      <form phx-submit="save" class="stack">
        <div class="title-block">
          <div class="row title-row">
            <span class="title-label">Title</span>
            <label class="toggle">
              <input
                type="checkbox"
                checked={@edit_title?}
                phx-click="toggle_edit_title"
              />
              <span>Edit title</span>
            </label>
          </div>

          <%= if @edit_title? do %>
            <input
              type="text"
              name="title"
              value={@title}
              required
              autofocus
              phx-change="title_change"
              phx-debounce="200"
              pattern={"[a-z]+-[a-z]+-[a-z0-9]{6}"}
              title="Format: shortword-shortword-xxxxxx"
              class="title-input"
            />
            <p class="hint">Use <code>shortword-shortword-xxxxxx</code> (6 alphanumeric).</p>
          <% else %>
            <input type="hidden" name="title" value={@title} />
            <div class="title-default row">
              <code class="title-generated">{@title}</code>
              <button type="button" class="btn btn-quiet btn-small" phx-click="regenerate_title">
                Regenerate
              </button>
            </div>
          <% end %>
        </div>

        <fieldset class="domain-fieldset">
          <legend>Domains</legend>
          <%= if @domains == [] do %>
            <p class="empty">
              No question sets visible. Run <code>mix isomer.db.sync</code> then
              <code>mix isomer.db.ensure_runtime</code>.
            </p>
          <% else %>
            <div class="domain-grid">
              <label :for={domain <- @domains} class="domain-option">
                <input
                  type="checkbox"
                  name={"domains[#{domain["id"]}]"}
                  value="true"
                  class="domain-option-input"
                />
                <div class="domain-option-panel">
                  <span class="domain-option-title">{domain["label"]}</span>
                  <p class="domain-option-desc">{domain["description"]}</p>
                  <p :if={domain["anchors"] not in [nil, []]} class="domain-option-anchors">
                    Anchors: {Enum.join(domain["anchors"] || [], ", ")}
                  </p>
                </div>
              </label>
            </div>
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
