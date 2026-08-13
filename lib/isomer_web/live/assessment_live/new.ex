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

    rulesets =
      case Tenant.list_rulesets(socket.assigns.surreal) do
        {:ok, rows} -> Enum.map(rows, &normalize_ruleset_option/1)
        {:error, _} -> []
      end

    domains = Domains.selectable(set_domains)
    title = Namegen.generate()

    {:ok,
     assign(socket,
       page_title: "New assessment",
       org_id: org_id,
       title: title,
       edit_title?: false,
       kind: "domains",
       domains: domains,
       rulesets: rulesets,
       selected_ruleset_id: default_ruleset_id(rulesets),
       error: nil,
       nav_org_id: org_id
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

  def handle_event("kind_change", %{"kind" => kind}, socket)
      when kind in ["domains", "ruleset", "combined"] do
    {:noreply, assign(socket, kind: kind, error: nil)}
  end

  def handle_event("kind_change", _params, socket), do: {:noreply, socket}

  def handle_event("ruleset_change", %{"ruleset_id" => ruleset_id}, socket) do
    {:noreply, assign(socket, selected_ruleset_id: ruleset_id, error: nil)}
  end

  def handle_event("save", params, socket) do
    kind = normalize_kind(Map.get(params, "kind") || socket.assigns.kind)

    selected_domains =
      params
      |> Map.get("domains", %{})
      |> Map.keys()

    ruleset_id =
      case kind do
        k when k in ["ruleset", "combined"] ->
          blank_to_nil(Map.get(params, "ruleset_id") || socket.assigns.selected_ruleset_id)

        _ ->
          nil
      end

    title =
      cond do
        socket.assigns.edit_title? ->
          params["title"] |> to_string() |> String.trim()

        true ->
          socket.assigns.title
      end

    title = if title == "", do: Namegen.generate(), else: title

    case validate_create(kind, selected_domains, ruleset_id, socket.assigns) do
      {:error, message} ->
        {:noreply, assign(socket, error: message, kind: kind, selected_ruleset_id: ruleset_id)}

      :ok ->
        attrs = %{
          "title" => title,
          "kind" => kind,
          "domains" => if(kind == "ruleset", do: [], else: selected_domains),
          "ruleset_id" => ruleset_id
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
  end

  defp validate_create("domains", domains, _ruleset_id, assigns) do
    cond do
      assigns.domains == [] ->
        {:error,
         "No question sets visible. Run mix isomer.db.sync then mix isomer.db.ensure_runtime."}

      domains == [] ->
        {:error, "Select at least one domain."}

      true ->
        :ok
    end
  end

  defp validate_create("ruleset", _domains, ruleset_id, assigns) do
    cond do
      assigns.rulesets == [] ->
        {:error,
         "No classification rulesets visible. Run mix isomer.db.sync then mix isomer.db.ensure_runtime."}

      is_nil(ruleset_id) ->
        {:error, "Select a classification ruleset."}

      true ->
        :ok
    end
  end

  defp validate_create("combined", domains, ruleset_id, assigns) do
    with :ok <- validate_create("ruleset", domains, ruleset_id, assigns) do
      validate_create("domains", domains, ruleset_id, assigns)
    end
  end

  defp normalize_kind(kind) when kind in ["domains", "ruleset", "combined"], do: kind
  defp normalize_kind(_), do: "domains"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_), do: nil

  defp default_ruleset_id([%{id: id} | _]), do: id
  defp default_ruleset_id(_), do: nil

  defp normalize_ruleset_option(row) when is_map(row) do
    id = row["corpus_id"] || row["ruleset"]

    %{
      id: id,
      label: row["ruleset"] || id,
      framework: row["framework"],
      status: row["status"]
    }
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  defp show_domains?(kind), do: kind in ["domains", "combined"]
  defp show_ruleset?(kind), do: kind in ["ruleset", "combined"]

  defp can_submit?(assigns) do
    case assigns.kind do
      "domains" -> assigns.domains != []
      "ruleset" -> assigns.rulesets != []
      "combined" -> assigns.domains != [] and assigns.rulesets != []
      _ -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <.h1>New assessment</.h1>
      <.p class="isomer-lede">
        Choose domain maturity questions, a regulatory classification ruleset, or both.
      </.p>
      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <.card>
        <.card_content>
          <form phx-submit="save" class="space-y-6">
            <div class="space-y-3">
              <span class="text-base font-medium text-slate-700 dark:text-slate-300">Title</span>

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
                <div class="flex flex-wrap items-center gap-2">
                  <.button
                    type="button"
                    color="gray"
                    variant="soft"
                    size="sm"
                    label="Use generated"
                    phx-click="toggle_edit_title"
                  />
                </div>
              <% else %>
                <input type="hidden" name="title" value={@title} />
                <div class="flex flex-wrap items-center gap-2">
                  <code class="title-generated">{@title}</code>
                  <.button
                    type="button"
                    color="gray"
                    variant="ghost"
                    size="sm"
                    label="Edit title"
                    phx-click="toggle_edit_title"
                  />
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
              <legend class="mb-2 text-base font-medium text-slate-700 dark:text-slate-300">
                Assessment type
              </legend>
              <div class="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
                <label class="domain-option">
                  <input
                    type="radio"
                    name="kind"
                    value="domains"
                    checked={@kind == "domains"}
                    phx-change="kind_change"
                    class="domain-option-input"
                  />
                  <div>
                    <span class="font-semibold text-slate-900 dark:text-slate-100">Domains</span>
                    <.p no_margin class="text-base text-slate-600 dark:text-slate-400">
                      Maturity questions only.
                    </.p>
                  </div>
                </label>
                <label class="domain-option">
                  <input
                    type="radio"
                    name="kind"
                    value="ruleset"
                    checked={@kind == "ruleset"}
                    phx-change="kind_change"
                    class="domain-option-input"
                  />
                  <div>
                    <span class="font-semibold text-slate-900 dark:text-slate-100">
                      Classification
                    </span>
                    <.p no_margin class="text-base text-slate-600 dark:text-slate-400">
                      Regulatory ruleset (e.g. EU AI Act) only.
                    </.p>
                  </div>
                </label>
                <label class="domain-option">
                  <input
                    type="radio"
                    name="kind"
                    value="combined"
                    checked={@kind == "combined"}
                    phx-change="kind_change"
                    class="domain-option-input"
                  />
                  <div>
                    <span class="font-semibold text-slate-900 dark:text-slate-100">Combined</span>
                    <.p no_margin class="text-base text-slate-600 dark:text-slate-400">
                      Classification then domain maturity.
                    </.p>
                  </div>
                </label>
              </div>
            </fieldset>

            <fieldset :if={show_ruleset?(@kind)}>
              <legend class="mb-2 text-base font-medium text-slate-700 dark:text-slate-300">
                Classification ruleset
              </legend>
              <%= if @rulesets == [] do %>
                <.alert
                  color="warning"
                  variant="soft"
                  with_icon
                  label="No rulesets visible. Run mix isomer.db.sync then mix isomer.db.ensure_runtime."
                />
              <% else %>
                <select
                  name="ruleset_id"
                  phx-change="ruleset_change"
                  class="answer-select__control w-full max-w-xl"
                >
                  {Phoenix.HTML.Form.options_for_select(
                    Enum.map(@rulesets, &{&1.label, &1.id}),
                    @selected_ruleset_id
                  )}
                </select>
                <.p
                  :if={selected_ruleset(@rulesets, @selected_ruleset_id)}
                  no_margin
                  class="mt-2 text-sm text-slate-500"
                >
                  Framework: {selected_ruleset(@rulesets, @selected_ruleset_id).framework}
                </.p>
              <% end %>
            </fieldset>

            <fieldset :if={show_domains?(@kind)}>
              <legend class="mb-2 text-base font-medium text-slate-700 dark:text-slate-300">
                Domains
              </legend>
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
                      <span class="font-semibold text-slate-900 dark:text-slate-100">
                        {domain["label"]}
                      </span>
                      <.p no_margin class="text-base text-slate-600 dark:text-slate-400">
                        {domain["description"]}
                      </.p>
                      <.p
                        :if={domain["anchors"] not in [nil, []]}
                        no_margin
                        class="mt-1 text-sm text-slate-500"
                      >
                        Anchors: {Enum.join(domain["anchors"] || [], ", ")}
                      </.p>
                    </div>
                  </label>
                </div>
              <% end %>
            </fieldset>

            <div class="flex flex-wrap gap-2">
              <.button type="submit" label="Create & open wizard" disabled={not can_submit?(assigns)} />
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

  defp selected_ruleset(rulesets, id) when is_binary(id),
    do: Enum.find(rulesets, &(&1.id == id))

  defp selected_ruleset(_, _), do: nil
end
