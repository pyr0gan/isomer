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
            answers = socket.assigns.answers

            {:noreply,
             socket
             |> assign(state)
             |> assign(:answers, answers)
             |> assign(:error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, error: format_error(reason))}
        end

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason))}
    end
  end

  def handle_event("answer", %{"question_id" => qid, "value" => value} = params, socket) do
    question = Enum.find(socket.assigns.questions, &(&1.id == qid))

    if is_nil(question) do
      {:noreply, assign(socket, error: "Unknown question")}
    else
      coerced = coerce_value(question.kind, value, params)

      attrs = %{
        "org_id" => socket.assigns.org_id,
        "assessment_id" => socket.assigns.assessment_id,
        "question_id" => qid,
        "pack" => "question_set",
        "pack_ref" => question.domain,
        "value" => coerced
      }

      case Tenant.upsert_answer(socket.assigns.surreal, attrs) do
        :ok ->
          answers = Map.put(socket.assigns.answers, qid, coerced)

          {:noreply,
           socket
           |> assign(:answers, answers)
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

  defp load_state(surreal, id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         {:ok, sets} <- Tenant.list_question_sets(surreal),
         {:ok, answers} <- Tenant.list_answers(surreal, id) do
      domains = assessment["domains"] || []
      questions = project_questions(sets, domains)
      answer_map = Map.new(answers, fn a -> {a["question_id"], a["value"]} end)
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
            <summary class="cursor-pointer font-medium text-slate-800">Add domains</summary>
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
                    <span class="font-semibold text-slate-900">{domain["label"]}</span>
                    <.p no_margin class="text-sm text-slate-600">{domain["description"]}</.p>
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
            <.p no_margin class="text-slate-600">No questions for the selected domains.</.p>
          </.card_content>
        </.card>
      <% else %>
        <.accordion
          container_id="wizard-domains"
          variant="bordered"
          multiple={true}
          open_index={0}
          class="rounded-xl bg-white/70 shadow-sm"
        >
          <:item
            :for={section <- @domain_sections}
            heading={"#{section.label}  ·  #{section.answered}/#{section.total}"}
          >
            <div class="wizard-domain-panel">
              <.p :if={section.description != ""} class="text-sm text-slate-600">
                {section.description}
              </.p>

              <.card :for={q <- section.questions} class="shadow-none">
                <.card_content class="space-y-3">
                  <div class="question-meta">
                    <.tooltip label={"Question id #{q.id}"} placement="top">
                      <code class="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-600">
                        {q.id}
                      </code>
                    </.tooltip>
                    <.level_badge :if={q.level} level={q.level} />
                  </div>

                  <.p no_margin class="text-base font-medium leading-snug text-slate-900">
                    {q.ask}
                  </.p>
                  <.p :if={q.evidence_prompt} no_margin class="text-sm text-slate-600">
                    <span class="font-medium text-slate-700">Evidence:</span>
                    {q.evidence_prompt}
                  </.p>

                  <form phx-submit="answer">
                    <input type="hidden" name="question_id" value={q.id} />
                    <div class="answer-controls">
                      <%= case q.kind do %>
                        <% "boolean" -> %>
                          <.field
                            type="radio-group"
                            name="value"
                            label="Answer"
                            options={[{"Yes", "true"}, {"No", "false"}]}
                            value={boolean_select_value(@answers[q.id])}
                            group_layout="row"
                            no_margin
                          />
                          <span
                            :if={@answers[q.id] == true}
                            class="answer-mark answer-mark-yes"
                            aria-label="Yes"
                          >
                            ✓
                          </span>
                          <span
                            :if={@answers[q.id] == false}
                            class="answer-mark answer-mark-no"
                            aria-label="No"
                          >
                            ✕
                          </span>
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
                          <span
                            :if={answered?(@answers, q.id)}
                            class="answer-mark answer-mark-yes"
                            aria-label="Saved"
                          >
                            ✓
                          </span>
                        <% _ -> %>
                          <.field
                            type="text"
                            name="value"
                            label="Answer"
                            value={to_string(@answers[q.id] || "")}
                            no_margin
                            wrapper_class="min-w-[14rem] flex-1"
                          />
                          <span
                            :if={answered?(@answers, q.id)}
                            class="answer-mark answer-mark-yes"
                            aria-label="Saved"
                          >
                            ✓
                          </span>
                      <% end %>
                      <.button
                        type="submit"
                        size="sm"
                        label={if answered?(@answers, q.id), do: "Edit", else: "Save"}
                        color={if answered?(@answers, q.id), do: "gray", else: "primary"}
                        variant={if answered?(@answers, q.id), do: "outline", else: "solid"}
                      />
                    </div>
                  </form>
                </.card_content>
              </.card>
            </div>
          </:item>
        </.accordion>
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
    <.tooltip label={"#{@level} — #{@meta.name}. #{@meta.tip}"} placement="top">
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

  defp boolean_select_value(true), do: "true"
  defp boolean_select_value(false), do: "false"
  defp boolean_select_value(_), do: ""

  defp coerce_value("boolean", value, _params) do
    case value do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp coerce_value("multi", value, _params) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp coerce_value(_kind, value, _params), do: value

  defp format_multi(list) when is_list(list), do: Enum.join(list, ", ")
  defp format_multi(other) when is_binary(other), do: other
  defp format_multi(_), do: ""
end
