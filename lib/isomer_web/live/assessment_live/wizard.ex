defmodule IsomerWeb.AssessmentLive.Wizard do
  use IsomerWeb.SurrealLive

  alias Isomer.Domains
  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy
  alias Isomer.Maturity
  alias Isomer.Ruleset.Evaluate

  @classification_section_id "__classification__"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    id = Tenant.canonicalize_record_id(id)

    case load_state(socket.assigns.surreal, id) do
      {:ok, state} ->
        open_ids =
          state.domain_sections
          |> List.first()
          |> case do
            %{id: section_id} -> MapSet.new([section_id])
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
    if socket.assigns.finalized do
      {:noreply, assign(socket, error: "This assessment is finalized and cannot be edited.")}
    else
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
              open = Map.get(socket.assigns, :open_domain_ids, MapSet.new())

              {:noreply,
               socket
               |> assign(state)
               |> assign(:open_domain_ids, open)
               |> assign(:error, nil)}

            {:error, reason} ->
              {:noreply, assign(socket, error: format_error(reason))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    end
  end

  def handle_event("toggle_domain_collect", %{"domain" => domain_id}, socket) do
    if socket.assigns.finalized do
      {:noreply, assign(socket, error: "This assessment is finalized and cannot be edited.")}
    else
      current = Map.get(socket.assigns.domain_metrics, domain_id, %{})
      collecting? = Map.get(current, "collect") in [true, "true", "on", 1, "1"]

      attrs =
        if collecting? do
          %{"collect" => false}
        else
          %{
            "collect" => true,
            "time_scale" => Map.get(current, "time_scale"),
            "time_hours" => Map.get(current, "time_hours")
          }
        end

      persist_domain_metric(socket, domain_id, attrs)
    end
  end

  def handle_event("save_domain_time", %{"domain" => domain_id} = params, socket) do
    if socket.assigns.finalized do
      {:noreply, assign(socket, error: "This assessment is finalized and cannot be edited.")}
    else
      attrs = %{
        "collect" => true,
        "time_scale" => Map.get(params, "time_scale", ""),
        "time_hours" => Map.get(params, "time_hours", "")
      }

      persist_domain_metric(socket, domain_id, attrs)
    end
  end

  def handle_event("answer", %{"question_id" => qid} = params, socket) do
    cond do
      socket.assigns.finalized ->
        {:noreply, assign(socket, error: "This assessment is finalized and cannot be edited.")}

      true ->
        question = Enum.find(socket.assigns.questions, &(&1.id == qid))

        if is_nil(question) do
          {:noreply, assign(socket, error: "Unknown question")}
        else
          # Radio groups (and some browsers) may send `value` as a list when a
          # hidden empty field is present; normalize before coerce.
          raw = Map.get(params, "value")
          coerced = coerce_value(question.kind, raw, params)
          evidence_note = evidence_note_from_params(params)

          if blank_answer?(question.kind, coerced) do
            clear_answer(socket, question, qid)
          else
            save_answer(socket, question, qid, coerced, evidence_note)
          end
        end
    end
  end

  defp blank_answer?("boolean", value), do: is_nil(value)
  defp blank_answer?("multi", value) when is_list(value), do: value == []
  defp blank_answer?(_kind, value), do: value in [nil, ""]

  defp clear_answer(socket, question, qid) do
    attrs = %{
      "assessment_id" => socket.assigns.assessment_id,
      "question_id" => qid,
      "pack" => question.pack,
      "pack_ref" => question.pack_ref
    }

    case Tenant.delete_answer(socket.assigns.surreal, attrs) do
      :ok ->
        answers = Map.delete(socket.assigns.answers, qid)
        notes = Map.delete(socket.assigns.evidence_notes, qid)

        socket =
          socket
          |> assign(:answers, answers)
          |> assign(:evidence_notes, notes)
          |> assign(
            :domain_sections,
            refresh_section_progress(socket.assigns.domain_sections, answers)
          )
          |> assign(:error, nil)

        {:noreply, maybe_reevaluate_classification(socket)}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp save_answer(socket, question, qid, coerced, evidence_note) do
    attrs = %{
      "org_id" => socket.assigns.org_id,
      "assessment_id" => socket.assigns.assessment_id,
      "question_id" => qid,
      "pack" => question.pack,
      "pack_ref" => question.pack_ref,
      "value" => pack_stored_value(coerced, evidence_note)
    }

    case Tenant.upsert_answer(socket.assigns.surreal, attrs) do
      :ok ->
        answers = Map.put(socket.assigns.answers, qid, coerced)
        notes = Map.put(socket.assigns.evidence_notes, qid, evidence_note)

        socket =
          socket
          |> assign(:answers, answers)
          |> assign(:evidence_notes, notes)
          |> assign(
            :domain_sections,
            refresh_section_progress(socket.assigns.domain_sections, answers)
          )
          |> assign(:error, nil)
          |> maybe_mark_in_progress()
          |> maybe_reevaluate_classification()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp maybe_mark_in_progress(socket) do
    status = socket.assigns.assessment["status"]

    if status in [nil, "", "draft"] do
      case Tenant.update_assessment_status(
             socket.assigns.surreal,
             socket.assigns.assessment_id,
             "in_progress"
           ) do
        {:ok, assessment} -> assign(socket, :assessment, assessment)
        {:error, _} -> socket
      end
    else
      socket
    end
  end

  defp maybe_reevaluate_classification(socket) do
    ruleset = socket.assigns[:ruleset]

    if is_nil(ruleset) do
      socket
    else
      ruleset_answers =
        socket.assigns.questions
        |> Enum.filter(&(&1.pack == "ruleset"))
        |> Enum.reduce(%{}, fn q, acc ->
          case Map.fetch(socket.assigns.answers, q.id) do
            {:ok, value} -> Map.put(acc, q.id, value)
            :error -> acc
          end
        end)

      result = Evaluate.evaluate(ruleset_doc(ruleset), ruleset_answers, %{})

      classification = %{
        "label" => result["classification"],
        "matched" => result["matched"],
        "outcome_index" => result["outcome_index"],
        "note" => result["note"],
        "ruleset" => result["ruleset"],
        "framework" => result["framework"]
      }

      activates =
        result["activates"]
        |> Enum.map(& &1["id"])
        |> Enum.reject(&is_nil/1)

      case Tenant.update_assessment_classification(
             socket.assigns.surreal,
             socket.assigns.assessment_id,
             classification,
             activates
           ) do
        {:ok, assessment} ->
          assign(socket,
            assessment: assessment,
            classification: classification,
            activates: activates
          )

        {:error, _} ->
          socket
      end
    end
  end

  defp ruleset_doc(row) when is_map(row) do
    %{
      "ruleset" => row["ruleset"] || row["corpus_id"],
      "framework" => row["framework"],
      "outcomes" => row["outcomes"] || [],
      "default_outcome" => row["default_outcome"],
      "questions" => row["questions"] || []
    }
  end

  defp persist_domain_metric(socket, domain_id, attrs) do
    case Tenant.update_domain_metric(
           socket.assigns.surreal,
           socket.assigns.assessment_id,
           domain_id,
           attrs
         ) do
      {:ok, assessment} ->
        metrics = normalize_domain_metrics(assessment["domain_metrics"])

        {:noreply,
         socket
         |> assign(:assessment, assessment)
         |> assign(:domain_metrics, metrics)
         |> assign(
           :domain_sections,
           attach_metric_flags(socket.assigns.domain_sections, metrics)
         )
         |> assign(:error, nil)
         |> then(&maybe_mark_in_progress/1)}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  defp load_state(surreal, id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         {:ok, sets} <- Tenant.list_question_sets(surreal),
         {:ok, answers} <- Tenant.list_answers(surreal, id),
         {:ok, ruleset} <- maybe_load_ruleset(surreal, assessment) do
      domains = assessment["domains"] || []
      domain_questions = project_domain_questions(sets, domains)
      ruleset_questions = project_ruleset_questions(ruleset)
      questions = ruleset_questions ++ domain_questions
      domain_metrics = normalize_domain_metrics(assessment["domain_metrics"])

      {answer_map, evidence_notes} =
        Enum.reduce(answers, {%{}, %{}}, fn a, {vals, notes} ->
          qid = a["question_id"]
          kind = Enum.find_value(questions, "text", fn q -> q.id == qid && q.kind end)
          {raw_value, note} = unpack_stored_value(a["value"])
          val = normalize_loaded_value(kind, raw_value)
          {Map.put(vals, qid, val), Map.put(notes, qid, note)}
        end)

      domain_sections =
        questions
        |> group_sections(answer_map)
        |> attach_metric_flags(domain_metrics)

      set_domains =
        sets
        |> Enum.map(& &1["domain"])
        |> Enum.reject(&is_nil/1)

      available = Domains.selectable(set_domains)
      addable = Enum.reject(available, &(&1["id"] in domains))

      org_id = Tenant.canonicalize_record_id(assessment["org"])

      {:ok,
       %{
         page_title: "Wizard · #{assessment["title"]}",
         assessment: assessment,
         assessment_id: id,
         org_id: org_id,
         ruleset: ruleset,
         classification: assessment["classification"],
         activates: assessment["activates"] || [],
         questions: questions,
         domain_sections: domain_sections,
         domain_metrics: domain_metrics,
         answers: answer_map,
         evidence_notes: evidence_notes,
         addable_domains: addable,
         finalized: finalized?(assessment),
         nav_org_id: org_id,
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

  defp normalize_domain_metrics(metrics) when is_map(metrics) and not is_struct(metrics),
    do: metrics

  defp normalize_domain_metrics(_), do: %{}

  defp attach_metric_flags(sections, metrics) do
    Enum.map(sections, fn section ->
      entry = Map.get(metrics, section.id, %{})
      collect? = Map.get(entry, "collect") in [true, "true", "on", 1, "1"]

      Map.merge(section, %{
        collect_metrics: collect?,
        time_scale: Map.get(entry, "time_scale") || "",
        time_hours: format_time_hours_input(Map.get(entry, "time_hours"))
      })
    end)
  end

  defp format_time_hours_input(nil), do: ""
  defp format_time_hours_input(n) when is_integer(n), do: Integer.to_string(n)
  defp format_time_hours_input(n) when is_float(n), do: :erlang.float_to_binary(n, [:short])
  defp format_time_hours_input(n) when is_binary(n), do: n
  defp format_time_hours_input(_), do: ""

  defp finalized?(%{"status" => status}) when status in ["complete", "archived"], do: true
  defp finalized?(_), do: false

  defp prefs_unset?(prefs) do
    prefs = GuideCopy.normalize(prefs)

    is_nil(prefs["self_role"]) and is_nil(prefs["experience_level"]) and
      is_nil(prefs["comfort_level"])
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
          <.h1 id="assessment-title" phx-hook="StickyTitle" data-sticky-title={@assessment["title"]}>
            {@assessment["title"]}
          </.h1>
          <.p class="isomer-lede">
            {GuideCopy.wizard_lede(@guide_prefs, @finalized)}
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
            to={~p"/assessments/#{@assessment_id}"}
            color="gray"
            variant="outline"
            label="Details"
            icon="hero-information-circle"
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
            color="primary"
            variant="outline"
            label={GuideCopy.artifacts_nav_label()}
            icon="hero-document-text"
          />
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <.alert
        :if={classification_label(@classification)}
        color="info"
        variant="soft"
        with_icon
        class="mb-4"
      >
        Classification: <span class="font-medium">{classification_label(@classification)}</span>
        <%= if is_list(@activates) and @activates != [] do %>
          · {length(@activates)} activated obligation(s)
        <% end %>
      </.alert>

      <.alert
        :if={@finalized}
        color="warning"
        variant="soft"
        with_icon
        class="mb-4"
      >
        This assessment is finalized. Reopen it from Details to edit answers.
        Or
        <.link
          navigate={~p"/assessments/#{@assessment_id}/artifacts"}
          class="font-medium underline underline-offset-2"
        >
          {GuideCopy.artifacts_nav_label() |> String.downcase()}
        </.link>
        for this run.
      </.alert>

      <.alert
        :if={not @finalized and prefs_unset?(@guide_prefs)}
        color="info"
        variant="soft"
        with_icon
        class="mb-4"
      >
        New here? Set your role and comfort in
        <.link navigate={~p"/settings"} class="font-medium underline underline-offset-2">
          Settings
        </.link>
        so tips stay plain-language (or concise) without changing the questionnaire.
      </.alert>

      <.card :if={not @finalized and @addable_domains != []} variant="muted">
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
                    <.p no_margin class="text-base text-slate-600 dark:text-slate-400">
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
              No questions for the selected domains or ruleset.
            </.p>
          </.card_content>
        </.card>
      <% else %>
        <%!-- LiveView-managed accordion (not Petal): Petal uses phx-update=ignore,
             which blocks answer/select patches until a full refresh. --%>
        <div id="wizard-domains" class="wizard-accordion rounded-xl bg-white/70 shadow-sm">
          <div :for={section <- @domain_sections} class="wizard-accordion__item" id={"domain-#{section.id}"}>
            <div class="wizard-accordion__header">
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
                  <span
                    id={"domain-#{section.id}-progress"}
                    class="wizard-progress"
                    title={"Yes #{section.yes} · No #{section.no} · Unanswered #{section.unanswered}"}
                  >
                    · {section.answered}/{section.total}
                    <span class="wizard-progress__detail">
                      ({section.yes} yes · {section.no} no · {section.unanswered} open)
                    </span>
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

              <label
                :if={section.collectable}
                class="wizard-domain-collect"
                title="Include this domain in org objective metrics"
              >
                <input
                  type="checkbox"
                  class="wizard-domain-collect__input"
                  phx-click="toggle_domain_collect"
                  phx-value-domain={section.id}
                  checked={section.collect_metrics}
                  disabled={@finalized}
                />
                <span class="wizard-domain-collect__label">Collect metrics</span>
              </label>
            </div>

            <div
              :if={MapSet.member?(@open_domain_ids, section.id)}
              id={"domain-#{section.id}-panel"}
              class="wizard-domain-panel wizard-accordion__panel"
              role="region"
              aria-labelledby={"domain-#{section.id}-toggle"}
            >
              <.p :if={section.description != ""} class="text-base text-slate-600 dark:text-slate-400">
                {section.description}
              </.p>

              <div :if={section.collect_metrics} class="wizard-domain-time">
                <%= if @finalized do %>
                  <p class="wizard-domain-time__readonly">
                    Time spent: {time_scale_label(section.time_scale)}
                    <%= if section.time_hours != "" do %>
                      · {section.time_hours}h
                    <% end %>
                  </p>
                <% else %>
                  <form
                    id={"domain-time-#{section.id}"}
                    phx-submit="save_domain_time"
                    class="wizard-domain-time__form"
                  >
                    <input type="hidden" name="domain" value={section.id} />
                    <div class="wizard-domain-time__field">
                      <label class="wizard-domain-time__label" for={"time-scale-#{section.id}"}>
                        Time scale
                      </label>
                      <select
                        id={"time-scale-#{section.id}"}
                        name="time_scale"
                        class="wizard-domain-time__control"
                      >
                        {Phoenix.HTML.Form.options_for_select(
                          [{"—", ""}, {"Low", "low"}, {"Medium", "medium"}, {"High", "high"}],
                          section.time_scale
                        )}
                      </select>
                    </div>
                    <div class="wizard-domain-time__field">
                      <label class="wizard-domain-time__label" for={"time-hours-#{section.id}"}>
                        Hours
                      </label>
                      <input
                        id={"time-hours-#{section.id}"}
                        type="number"
                        name="time_hours"
                        min="0"
                        step="0.5"
                        value={section.time_hours}
                        placeholder="0"
                        class="wizard-domain-time__control wizard-domain-time__hours"
                      />
                    </div>
                    <.button type="submit" size="sm" label="Save time" color="gray" variant="outline" />
                  </form>
                <% end %>
              </div>

              <.card :for={q <- section.questions} class="wizard-question-card shadow-none">
                <.card_content class="wizard-question-card__body space-y-3">
                  <div class="wizard-question-card__status" aria-hidden="true">
                    <.icon
                      :if={q.kind == "boolean" and truthy_answer?(@answers[q.id])}
                      name="hero-check-circle-solid"
                      class="answer-mark-icon answer-mark-icon-yes"
                    />
                    <.icon
                      :if={q.kind == "boolean" and falsey_answer?(@answers[q.id])}
                      name="hero-x-circle-solid"
                      class="answer-mark-icon answer-mark-icon-no"
                    />
                    <.icon
                      :if={q.kind != "boolean" and answered?(@answers, q.id)}
                      name="hero-check-circle-solid"
                      class="answer-mark-icon answer-mark-icon-yes"
                    />
                  </div>

                  <div class="question-meta">
                    <.tooltip label={"Question id #{q.id}"} placement="right">
                      <code class="rounded bg-slate-100 px-1.5 py-0.5 text-sm text-slate-600 dark:bg-slate-800 dark:text-slate-300">
                        {q.id}
                      </code>
                    </.tooltip>
                    <.level_badge :if={q.level} level={q.level} />
                  </div>

                  <.p
                    no_margin
                    class="text-lg font-medium leading-snug text-slate-900 dark:text-slate-100"
                  >
                    {q.ask}
                  </.p>

                  <.p
                    :if={GuideCopy.question_help(@guide_prefs, q)}
                    no_margin
                    class="text-base text-slate-500 dark:text-slate-400"
                  >
                    {GuideCopy.question_help(@guide_prefs, q)}
                  </.p>

                  <%= if @finalized do %>
                    <div class="answer-readonly text-base text-slate-700 dark:text-slate-300">
                      <span class="font-medium">Answer:</span>
                      {format_answer_display(q.kind, @answers[q.id])}
                      <span
                        :if={Map.get(@evidence_notes, q.id, "") != ""}
                        class="mt-1 block text-slate-500"
                      >
                        Evidence: {Map.get(@evidence_notes, q.id, "")}
                      </span>
                    </div>
                  <% else %>
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
                          <% "single" -> %>
                            <div class="answer-select">
                              <label class="answer-select__label" for={"answer-select-#{q.id}"}>
                                Answer
                              </label>
                              <select
                                id={"answer-select-#{q.id}-#{to_string(@answers[q.id] || "")}"}
                                name="value"
                                class="answer-select__control"
                              >
                                {Phoenix.HTML.Form.options_for_select(
                                  [{"—", ""} | Enum.map(q.options || [], &{&1, &1})],
                                  to_string(@answers[q.id] || "")
                                )}
                              </select>
                            </div>
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
                          <% _ -> %>
                            <.field
                              type="text"
                              name="value"
                              label="Answer"
                              value={to_string(@answers[q.id] || "")}
                              no_margin
                              wrapper_class="min-w-[14rem] flex-1"
                            />
                        <% end %>
                        <.button
                          type="submit"
                          size="sm"
                          label={if answered?(@answers, q.id), do: "Update", else: "Save"}
                          color={if answered?(@answers, q.id), do: "gray", else: "primary"}
                          variant={if answered?(@answers, q.id), do: "outline", else: "solid"}
                        />
                      </div>

                      <.field
                        :if={
                          q.evidence_prompt || GuideCopy.guided?(@guide_prefs)
                        }
                        type="textarea"
                        rows="3"
                        name="evidence"
                        label="Evidence"
                        help_text={GuideCopy.evidence_help_text(@guide_prefs, q.evidence_prompt)}
                        value={Map.get(@evidence_notes, q.id, "")}
                        placeholder="Short note or reference"
                        class="answer-evidence"
                      />
                    </form>
                  <% end %>
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
    meta = Maturity.level_meta(assigns.level)
    assigns = assign(assigns, :meta, meta)

    ~H"""
    <.tooltip label={"#{@meta.label} — #{@meta.tip}"} placement="right">
      <.badge color={@meta.color} variant="soft" label={@meta.label} class="cursor-help" />
    </.tooltip>
    """
  end

  defp project_domain_questions(sets, domains) do
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
          options: q["options"] || [],
          domain: domain,
          pack: "question_set",
          pack_ref: domain,
          collectable: true
        }
      end)
    end)
  end

  defp project_ruleset_questions(nil), do: []

  defp project_ruleset_questions(ruleset) when is_map(ruleset) do
    pack_ref = ruleset["corpus_id"] || ruleset["ruleset"]

    (ruleset["questions"] || [])
    |> Enum.map(fn q ->
      %{
        id: q["id"],
        ask: question_ask(q),
        evidence_prompt: q["evidence_prompt"] || q["help"],
        level: nil,
        kind: q["kind"] || "text",
        options: q["options"] || [],
        domain: @classification_section_id,
        pack: "ruleset",
        pack_ref: pack_ref,
        collectable: false
      }
    end)
  end

  defp group_sections(questions, answers) do
    catalog = Map.new(Domains.catalog(), &{&1["id"], &1})

    questions
    |> Enum.group_by(& &1.domain)
    |> Enum.map(fn {domain_id, qs} ->
      counts = progress_counts(qs, answers)
      collectable? = Enum.any?(qs, & &1.collectable)

      {label, description} =
        if domain_id == @classification_section_id do
          {"Classification", "Regulatory classification questions for this assessment."}
        else
          meta = Map.get(catalog, domain_id, %{})

          {meta["label"] || Domains.sentence_case(domain_id), meta["description"] || ""}
        end

      %{
        id: domain_id,
        label: label,
        description: description,
        questions: qs,
        total: counts.total,
        answered: counts.answered,
        yes: counts.yes,
        no: counts.no,
        unanswered: counts.unanswered,
        collectable: collectable?
      }
    end)
    |> Enum.sort_by(fn section ->
      cond do
        section.id == @classification_section_id -> -1
        true -> Enum.find_index(Domains.catalog(), &(&1["id"] == section.id)) || 999
      end
    end)
  end

  defp refresh_section_progress(sections, answers) do
    Enum.map(sections, fn section ->
      counts = progress_counts(section.questions, answers)

      %{
        section
        | total: counts.total,
          answered: counts.answered,
          yes: counts.yes,
          no: counts.no,
          unanswered: counts.unanswered
      }
    end)
  end

  defp progress_counts(questions, answers) do
    total = length(questions)

    {yes, no, other} =
      Enum.reduce(questions, {0, 0, 0}, fn q, {y, n, o} ->
        case answer_bucket(q.kind, Map.get(answers, q.id, :missing)) do
          :yes -> {y + 1, n, o}
          :no -> {y, n + 1, o}
          :answered -> {y, n, o + 1}
          :unanswered -> {y, n, o}
        end
      end)

    answered = yes + no + other
    unanswered = total - answered

    %{
      total: total,
      answered: answered,
      yes: yes,
      no: no,
      unanswered: unanswered
    }
  end

  # Boolean No must count as answered (bucket :no), not unanswered.
  defp answer_bucket("boolean", value) do
    case normalize_loaded_value("boolean", value) do
      true -> :yes
      false -> :no
      _ -> :unanswered
    end
  end

  defp answer_bucket(_kind, :missing), do: :unanswered
  defp answer_bucket(_kind, nil), do: :unanswered
  defp answer_bucket(_kind, ""), do: :unanswered
  defp answer_bucket("multi", list) when is_list(list) and list == [], do: :unanswered
  defp answer_bucket(_kind, _), do: :answered

  defp question_ask(q) when is_map(q) do
    q["ask"] || q["prompt"] || q["text"] || q["id"] || "Untitled question"
  end

  defp answered?(answers, id) do
    case Map.fetch(answers, id) do
      :error -> false
      {:ok, value} -> answer_bucket("text", value) != :unanswered
    end
  end

  defp format_answer_display("boolean", value) do
    case normalize_loaded_value("boolean", value) do
      true -> "Yes"
      false -> "No"
      _ -> "—"
    end
  end

  defp format_answer_display("multi", value), do: format_multi(value) |> blank_as_dash()
  defp format_answer_display(_kind, value), do: value |> to_string() |> blank_as_dash()

  defp blank_as_dash(""), do: "—"
  defp blank_as_dash(value), do: value

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

  defp coerce_value("single", value, _params) do
    case unwrap_param(value) do
      nil -> nil
      "" -> nil
      other -> to_string(other)
    end
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

  defp classification_label(%{"label" => label}) when is_binary(label) and label != "", do: label

  defp classification_label(%{"classification" => label}) when is_binary(label) and label != "",
    do: label

  defp classification_label(_), do: nil

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

  defp time_scale_label("low"), do: "Low"
  defp time_scale_label("medium"), do: "Medium"
  defp time_scale_label("high"), do: "High"
  defp time_scale_label(_), do: "—"
end
