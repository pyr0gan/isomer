defmodule IsomerWeb.AssessmentLive.Wizard do
  use IsomerWeb.SurrealLive

  alias Isomer.Domains
  alias Isomer.Db.Tenant

  @maturity_levels %{
    "L0" => %{
      name: "Ad hoc / Unaware",
      color: "gray",
      tip: "No structured practice yet — work happens without governance awareness."
    },
    "L1" => %{
      name: "Foundational",
      color: "info",
      tip: "Foundational — first policies or practices exist on paper and are communicated."
    },
    "L2" => %{
      name: "Defined",
      color: "primary",
      tip: "Defined — working, reviewable system ready for certification-style scrutiny."
    },
    "L3" => %{
      name: "Measured",
      color: "success",
      tip: "Measured / certified — steered by KPIs, audits, or certification evidence."
    },
    "L4" => %{
      name: "Optimizing",
      color: "warning",
      tip: "Optimizing — anticipates change and treats governance as a strategic capability."
    }
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = Tenant.canonicalize_record_id(id)

    case load_state(socket.assigns.surreal, id) do
      {:ok, state} ->
        open_ids =
          state.domain_sections
          |> List.first()
          |> case do
            %{id: id} -> MapSet.new([id])
            _ -> MapSet.new()
          end

        {:ok,
         socket
         |> assign(state)
         |> assign(error: nil, open_domain_ids: open_ids)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Assessment not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("toggle_domain", %{"id" => domain_id}, socket) do
    open = socket.assigns.open_domain_ids

    open =
      if MapSet.member?(open, domain_id) do
        MapSet.delete(open, domain_id)
      else
        MapSet.put(open, domain_id)
      end

    {:noreply, assign(socket, open_domain_ids: open)}
  end

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
            answers = socket.assigns.answers
            notes = Map.get(socket.assigns, :evidence_notes, %{})
            open = Map.get(socket.assigns, :open_domain_ids, MapSet.new())

            {:noreply,
             socket
             |> assign(state)
             |> assign(:answers, answers)
             |> assign(:evidence_notes, notes)
             |> assign(:open_domain_ids, open)
             |> assign(:error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  def handle_event("answer", %{"question_id" => qid} = params, socket) do
    question = Enum.find(socket.assigns.questions, &(&1.id == qid))

    if is_nil(question) do
      {:noreply, assign(socket, error: "Unknown question")}
    else
      # Radio groups (and some browsers) may send `value` as a list when a
      # hidden empty field is present; normalize before coerce.
      raw = Map.get(params, "value")
      coerced = coerce_value(question.kind, raw, params)
      evidence_note = evidence_note_from_params(params)

      if question.kind == "boolean" and is_nil(coerced) do
        {:noreply, assign(socket, error: "Choose Yes or No before saving")}
      else
        attrs = %{
          "org_id" => socket.assigns.org_id,
          "assessment_id" => socket.assigns.assessment_id,
          "question_id" => qid,
          "pack" => "question_set",
          "pack_ref" => question.domain,
          "value" => pack_stored_value(coerced, evidence_note)
        }

        case Tenant.upsert_answer(socket.assigns.surreal, attrs) do
          :ok ->
            answers = Map.put(socket.assigns.answers, qid, coerced)
            notes = Map.put(socket.assigns.evidence_notes, qid, evidence_note)

            {:noreply,
             socket
             |> assign(:answers, answers)
             |> assign(:evidence_notes, notes)
             |> assign(
               :domain_sections,
               refresh_section_progress(socket.assigns.domain_sections, answers)
             )
             |> assign(:error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end
      end
    end
  end

  defp load_state(surreal, id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         {:ok, sets} <- Tenant.list_question_sets(surreal),
         {:ok, answers} <- Tenant.list_answers(surreal, id) do
      domains = assessment["domains"] || []
      questions = project_questions(sets, domains)

      {answer_map, evidence_notes} =
        Enum.reduce(answers, {%{}, %{}}, fn a, {vals, notes} ->
          qid = a["question_id"]
          kind = Enum.find_value(questions, "text", fn q -> q.id == qid && q.kind end)
          {raw_value, note} = unpack_stored_value(a["value"])
          val = normalize_loaded_value(kind, raw_value)
          {Map.put(vals, qid, val), Map.put(notes, qid, note)}
        end)

      domain_sections = group_by_domain(questions, answer_map)

      set_domains =
        sets
        |> Enum.map(& &1["domain"])
        |> Enum.reject(&is_nil/1)

      available = Domains.selectable(set_domains)
      addable = Enum.reject(available, &(&1["id"] in domains))

      {:ok,
       %{
         page_title: "Wizard · #{assessment["title"]}",
         assessment: assessment,
         assessment_id: id,
         org_id: Tenant.canonicalize_record_id(assessment["org"]),
         questions: questions,
         domain_sections: domain_sections,
         answers: answer_map,
         evidence_notes: evidence_notes,
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
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>{@assessment["title"]}</.h1>
          <.p class="isomer-lede">
            Work domain by domain. Each answer is saved with your Surreal user JWT.
          </.p>
        </div>
        <.button
          link_type="live_redirect"
          to={~p"/assessments/#{@assessment_id}"}
          color="gray"
          variant="outline"
          label="Details"
          icon="hero-information-circle"
        />
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <.card :if={@addable_domains != []} variant="muted">
        <.card_content>
          <details>
            <summary class="cursor-pointer font-medium text-slate-800 dark:text-slate-200">
              Add domains
            </summary>
            <form phx-submit="add_domains" class="mt-4 space-y-4">
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
                    <.p no_margin class="text-sm text-slate-600 dark:text-slate-400">
                      {domain["description"]}
                    </.p>
                  </div>
                </label>
              </div>
              <.button type="submit" label="Add selected domains" size="sm" />
            </form>
          </details>
        </.card_content>
      </.card>

      <%= if @domain_sections == [] do %>
        <.card variant="muted">
          <.card_content>
            <.p no_margin class="text-slate-600 dark:text-slate-400">
              No questions for the selected domains.
            </.p>
          </.card_content>
        </.card>
      <% else %>
        <%!-- LiveView-managed accordion (not Petal): Petal uses phx-update=ignore,
             which blocks answer/select patches until a full refresh. --%>
        <div id="wizard-domains" class="wizard-accordion rounded-xl bg-white/70 shadow-sm">
          <div :for={section <- @domain_sections} class="wizard-accordion__item" id={"domain-#{section.id}"}>
            <button
              type="button"
              id={"domain-#{section.id}-toggle"}
              class="wizard-accordion__trigger"
              phx-click="toggle_domain"
              phx-value-id={section.id}
              aria-expanded={"#{MapSet.member?(@open_domain_ids, section.id)}"}
              aria-controls={"domain-#{section.id}-panel"}
            >
              <span class="wizard-accordion__heading">
                {section.label}
                <span class="wizard-progress">
                  · {section.answered}/{section.total}
                </span>
              </span>
              <.icon
                name="hero-chevron-down-solid"
                class={[
                  "wizard-accordion__chevron",
                  MapSet.member?(@open_domain_ids, section.id) && "rotate-180"
                ]}
              />
            </button>

            <div
              :if={MapSet.member?(@open_domain_ids, section.id)}
              id={"domain-#{section.id}-panel"}
              class="wizard-domain-panel wizard-accordion__panel"
              role="region"
              aria-labelledby={"domain-#{section.id}-toggle"}
            >
              <.p :if={section.description != ""} class="text-sm text-slate-600 dark:text-slate-400">
                {section.description}
              </.p>

              <.card :for={q <- section.questions} class="wizard-question-card shadow-none">
                <.card_content class="space-y-3">
                  <div class="question-meta">
                    <.tooltip label={"Question id #{q.id}"} placement="bottom">
                      <code class="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-600 dark:bg-slate-800 dark:text-slate-300">
                        {q.id}
                      </code>
                    </.tooltip>
                    <.level_badge :if={q.level} level={q.level} />
                  </div>

                  <.p
                    no_margin
                    class="text-base font-medium leading-snug text-slate-900 dark:text-slate-100"
                  >
                    {q.ask}
                  </.p>

                  <form id={"answer-form-#{q.id}"} phx-submit="answer" class="answer-form">
                    <input type="hidden" name="question_id" value={q.id} />
                    <div class="answer-controls">
                      <%= case q.kind do %>
                        <% "boolean" -> %>
                          <div class="answer-select">
                            <label class="answer-select__label" for={"answer-select-#{q.id}"}>
                              Answer
                            </label>
                            <select
                              id={"answer-select-#{q.id}-#{boolean_select_value(@answers[q.id])}"}
                              name="value"
                              class="answer-select__control"
                            >
                              {Phoenix.HTML.Form.options_for_select(
                                [{"—", ""}, {"Yes", "yes"}, {"No", "no"}],
                                boolean_select_value(@answers[q.id])
                              )}
                            </select>
                          </div>
                          <.icon
                            :if={truthy_answer?(@answers[q.id])}
                            name="hero-check-circle-solid"
                            class="answer-mark-icon answer-mark-icon-yes"
                          />
                          <.icon
                            :if={falsey_answer?(@answers[q.id])}
                            name="hero-x-circle-solid"
                            class="answer-mark-icon answer-mark-icon-no"
                          />
                        <% "multi" -> %>
                          <.field
                            type="text"
                            name="value"
                            label="Answer"
                            placeholder="comma-separated"
                            value={format_multi(@answers[q.id])}
                            no_margin
                            wrapper_class="min-w-[14rem] flex-1"
                          />
                          <.icon
                            :if={answered?(@answers, q.id)}
                            name="hero-check-circle-solid"
                            class="answer-mark-icon answer-mark-icon-yes"
                          />
                        <% _ -> %>
                          <.field
                            type="text"
                            name="value"
                            label="Answer"
                            value={to_string(@answers[q.id] || "")}
                            no_margin
                            wrapper_class="min-w-[14rem] flex-1"
                          />
                          <.icon
                            :if={answered?(@answers, q.id)}
                            name="hero-check-circle-solid"
                            class="answer-mark-icon answer-mark-icon-yes"
                          />
                      <% end %>
                      <.button
                        type="submit"
                        size="sm"
                        label={if answered?(@answers, q.id), do: "Edit", else: "Save"}
                        color={if answered?(@answers, q.id), do: "gray", else: "primary"}
                        variant={if answered?(@answers, q.id), do: "outline", else: "solid"}
                      />
                    </div>

                    <.field
                      :if={q.evidence_prompt}
                      type="text"
                      name="evidence"
                      label="Evidence"
                      help_text={q.evidence_prompt}
                      value={Map.get(@evidence_notes, q.id, "")}
                      placeholder="Short note or reference for now"
                      class="answer-evidence"
                    />
                  </form>
                </.card_content>
              </.card>
            </div>
          </div>
        </div>
      <% end %>
    </section>
    """
  end

  attr(:level, :string, required: true)

  def level_badge(assigns) do
    meta =
      Map.get(@maturity_levels, assigns.level, %{
        name: assigns.level,
        color: "gray",
        tip: assigns.level
      })

    assigns = assign(assigns, :meta, meta)

    ~H"""
    <.tooltip label={"#{@level} — #{@meta.name}. #{@meta.tip}"} placement="bottom">
      <.badge color={@meta.color} variant="soft" label={@level} class="cursor-help" />
    </.tooltip>
    """
  end

  defp project_questions(sets, domains) do
    domain_set = MapSet.new(domains)

    sets
    |> Enum.filter(fn set -> MapSet.member?(domain_set, set["domain"]) end)
    |> Enum.flat_map(fn set ->
      domain = set["domain"]

      (set["questions"] || [])
      |> Enum.map(fn q ->
        %{
          id: q["id"],
          ask: question_ask(q),
          evidence_prompt: q["evidence_prompt"],
          level: q["level"],
          kind: q["kind"] || "text",
          domain: domain
        }
      end)
    end)
  end

  defp group_by_domain(questions, answers) do
    catalog = Map.new(Domains.catalog(), &{&1["id"], &1})

    questions
    |> Enum.group_by(& &1.domain)
    |> Enum.map(fn {domain_id, qs} ->
      meta = Map.get(catalog, domain_id, %{})
      total = length(qs)
      answered = Enum.count(qs, &answered?(answers, &1.id))

      %{
        id: domain_id,
        label: meta["label"] || Domains.sentence_case(domain_id),
        description: meta["description"] || "",
        questions: qs,
        total: total,
        answered: answered
      }
    end)
    |> Enum.sort_by(fn section ->
      Enum.find_index(Domains.catalog(), &(&1["id"] == section.id)) || 999
    end)
  end

  defp refresh_section_progress(sections, answers) do
    Enum.map(sections, fn section ->
      answered = Enum.count(section.questions, &answered?(answers, &1.id))
      %{section | answered: answered}
    end)
  end

  defp question_ask(q) when is_map(q) do
    q["ask"] || q["prompt"] || q["text"] || q["id"] || "Untitled question"
  end

  defp answered?(answers, id) do
    case Map.fetch(answers, id) do
      {:ok, nil} -> false
      {:ok, ""} -> false
      {:ok, _} -> true
      :error -> false
    end
  end

  defp truthy_answer?(value), do: normalize_loaded_value("boolean", value) == true
  defp falsey_answer?(value), do: normalize_loaded_value("boolean", value) == false

  # Select option values are "yes" / "no" (not "true" / "false") so LiveView
  # never drops a falsey phx-value / button.value overwrite for "false".
  defp boolean_select_value(value) do
    case normalize_loaded_value("boolean", value) do
      true -> "yes"
      false -> "no"
      _ -> ""
    end
  end

  defp normalize_loaded_value("boolean", value) do
    case unwrap_param(value) do
      v when v in [true, "true", "yes", 1, "1"] -> true
      v when v in [false, "false", "no", 0, "0"] -> false
      _ -> nil
    end
  end

  defp normalize_loaded_value(_kind, value), do: value

  defp coerce_value("boolean", value, _params) do
    normalize_loaded_value("boolean", value)
  end

  defp coerce_value("multi", value, _params) do
    value
    |> unwrap_param()
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp coerce_value(_kind, value, _params), do: unwrap_param(value)

  # Prefer the last non-empty entry when duplicate form fields are submitted.
  defp unwrap_param(value) when is_list(value) do
    value
    |> Enum.reject(&(&1 in [nil, ""]))
    |> List.last()
  end

  defp unwrap_param(value), do: value

  defp evidence_note_from_params(params) do
    params
    |> Map.get("evidence", "")
    |> unwrap_param()
    |> to_string()
    |> String.trim()
  end

  # MVP: keep a short evidence note beside the answer value until file upload exists.
  # Shape: %{"v" => <answer>, "evidence" => <note>} — plain values remain supported.
  defp pack_stored_value(coerced, evidence_note) when evidence_note in [nil, ""], do: coerced

  defp pack_stored_value(coerced, evidence_note) do
    %{"v" => coerced, "evidence" => evidence_note}
  end

  defp unpack_stored_value(%{"v" => value} = map) when is_map(map) do
    {value, map |> Map.get("evidence", "") |> to_string()}
  end

  defp unpack_stored_value(value), do: {value, ""}

  defp format_multi(list) when is_list(list), do: Enum.join(list, ", ")
  defp format_multi(other) when is_binary(other), do: other
  defp format_multi(_), do: ""
end
