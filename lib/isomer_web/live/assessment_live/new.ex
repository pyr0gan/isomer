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
    <section class="isomer-page">
      <.h1>New assessment</.h1>
      <.p class="isomer-lede">
        Pick one or more question-set domains from the published corpus.
      </.p>
      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <.card>
        <.card_content>
          <form phx-submit="save" class="space-y-6">
            <div class="space-y-3">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="text-sm font-medium text-slate-700">Title</span>
                <.button
                  type="button"
                  color="gray"
                  variant={if @edit_title?, do: "soft", else: "ghost"}
                  size="sm"
                  label={if @edit_title?, do: "Use generated", else: "Edit title"}
                  phx-click="toggle_edit_title"
                />
              </div>

              <%= if @edit_title? do %>
                <.field
                  type="text"
                  name="title"
                  label="Custom title"
                  value={@title}
                  required
                  autofocus
                  phx-change="title_change"
                  phx-debounce="200"
                  pattern={"[a-z]+-[a-z]+-[a-z0-9]{6}"}
                  help_text="Format: shortword-shortword-xxxxxx (6 alphanumeric)."
                />
              <% else %>
                <input type="hidden" name="title" value={@title} />
                <div class="flex flex-wrap items-center gap-2">
                  <code class="title-generated">{@title}</code>
                  <.button
                    type="button"
                    color="gray"
                    variant="ghost"
                    size="sm"
                    label="Regenerate"
                    icon="hero-arrow-path"
                    phx-click="regenerate_title"
                  />
                </div>
              <% end %>
            </div>

            <fieldset>
              <legend class="mb-2 text-sm font-medium text-slate-700">Domains</legend>
              <%= if @domains == [] do %>
                <.alert
                  color="warning"
                  variant="soft"
                  with_icon
                  label="No question sets visible. Run mix isomer.db.sync then mix isomer.db.ensure_runtime."
                />
              <% else %>
                <div class="domain-grid">
                  <label :for={domain <- @domains} class="domain-option">
                    <input
                      type="checkbox"
                      name={"domains[#{domain["id"]}]"}
                      value="true"
                      class="domain-option-input"
                    />
                    <div>
                      <span class="font-semibold text-slate-900">{domain["label"]}</span>
                      <.p no_margin class="text-sm text-slate-600">{domain["description"]}</.p>
                      <.p
                        :if={domain["anchors"] not in [nil, []]}
                        no_margin
                        class="mt-1 text-xs text-slate-500"
                      >
                        Anchors: {Enum.join(domain["anchors"] || [], ", ")}
                      </.p>
                    </div>
                  </label>
                </div>
              <% end %>
            </fieldset>

            <div class="flex flex-wrap gap-2">
              <.button type="submit" label="Create & open wizard" disabled={@domains == []} />
              <.button
                link_type="live_redirect"
                to={~p"/orgs/#{@org_id}"}
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
