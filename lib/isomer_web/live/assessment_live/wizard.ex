defmodule IsomerWeb.AssessmentLive.Wizard do
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
            # Keep existing answers map; reload may include new questions.
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
          {:noreply,
           socket
           |> assign(:answers, Map.put(socket.assigns.answers, qid, coerced))
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
    <section>
      <div class="row">
        <h1>{@assessment["title"]}</h1>
        <.link navigate={~p"/assessments/#{@assessment_id}"} class="btn btn-quiet">Details</.link>
      </div>
      <p class="lede">Answer questions; each save writes an `answer` row with your Surreal JWT.</p>
      <p :if={@error} class="error" role="alert">{@error}</p>

      <details :if={@addable_domains != []} class="add-domains">
        <summary>Add domains</summary>
        <form phx-submit="add_domains" class="stack">
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
          <button type="submit" class="btn btn-small">Add selected domains</button>
        </form>
      </details>

      <%= if @questions == [] do %>
        <p class="empty">No questions for the selected domains.</p>
      <% else %>
        <ol class="wizard">
          <li :for={q <- @questions} class="q">
            <div class="q-head">
              <code>{q.id}</code>
              <span class="meta">{q.domain}</span>
              <span :if={q.level} class="meta">{q.level}</span>
            </div>
            <p class="q-ask">{q.ask}</p>
            <p :if={q.evidence_prompt} class="q-evidence">{q.evidence_prompt}</p>
            <form phx-submit="answer" class="answer-form">
              <input type="hidden" name="question_id" value={q.id} />
              <div class="answer-controls">
                <%= case q.kind do %>
                  <% "boolean" -> %>
                    <select name="value" class="answer-input">
                      <option value="">—</option>
                      <option value="true" selected={@answers[q.id] == true}>Yes</option>
                      <option value="false" selected={@answers[q.id] == false}>No</option>
                    </select>
                    <span
                      :if={@answers[q.id] == true}
                      class="answer-mark answer-mark-yes"
                      aria-label="Yes"
                      title="Yes"
                    >
                      ✓
                    </span>
                    <span
                      :if={@answers[q.id] == false}
                      class="answer-mark answer-mark-no"
                      aria-label="No"
                      title="No"
                    >
                      ✕
                    </span>
                  <% "multi" -> %>
                    <input
                      type="text"
                      name="value"
                      class="answer-input"
                      placeholder="comma-separated"
                      value={format_multi(@answers[q.id])}
                    />
                    <span
                      :if={answered?(@answers, q.id)}
                      class="answer-mark answer-mark-yes"
                      aria-label="Saved"
                    >
                      ✓
                    </span>
                  <% _ -> %>
                    <input
                      type="text"
                      name="value"
                      class="answer-input"
                      value={to_string(@answers[q.id] || "")}
                    />
                    <span
                      :if={answered?(@answers, q.id)}
                      class="answer-mark answer-mark-yes"
                      aria-label="Saved"
                    >
                      ✓
                    </span>
                <% end %>
                <button type="submit" class="btn btn-small">
                  {if answered?(@answers, q.id), do: "Edit", else: "Save"}
                </button>
              </div>
            </form>
          </li>
        </ol>
      <% end %>
    </section>
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

  # Corpus YAML uses `ask`; tolerate older aliases if present in synced rows.
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
