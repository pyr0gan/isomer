defmodule IsomerWeb.AssessmentLive.Wizard do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    surreal = socket.assigns.surreal
    id = Tenant.canonicalize_record_id(id)

    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         {:ok, sets} <- Tenant.list_question_sets(surreal),
         {:ok, answers} <- Tenant.list_answers(surreal, id) do
      domains = assessment["domains"] || []
      questions = project_questions(sets, domains)
      answer_map = Map.new(answers, fn a -> {a["question_id"], a["value"]} end)

      {:ok,
       assign(socket,
         page_title: "Wizard · #{assessment["title"]}",
         assessment: assessment,
         assessment_id: id,
         org_id: Tenant.canonicalize_record_id(assessment["org"]),
         questions: questions,
         answers: answer_map,
         notice: nil,
         error: nil
       )}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Assessment not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end


  @impl true
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
           |> assign(:notice, "Saved #{qid}")
           |> assign(:error, nil)}

        {:error, reason} ->
          {:noreply, assign(socket, error: inspect(reason))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <div class="row">
        <h1>{@assessment["title"]}</h1>
        <.link navigate={~p"/assessments/#{@assessment_id}"} class="btn btn-quiet">Details</.link>
      </div>
      <p class="lede">Answer questions; each save writes an `answer` row with your Surreal JWT.</p>
      <p :if={@notice} class="flash flash-info">{@notice}</p>
      <p :if={@error} class="error" role="alert">{@error}</p>

      <%= if @questions == [] do %>
        <p class="empty">No questions for the selected domains.</p>
      <% else %>
        <ol class="wizard">
          <li :for={q <- @questions} class="q">
            <div class="q-head">
              <code>{q.id}</code>
              <span class="meta">{q.domain}</span>
            </div>
            <p>{q.prompt}</p>
            <form phx-submit="answer" class="stack">
              <input type="hidden" name="question_id" value={q.id} />
              <%= case q.kind do %>
                <% "boolean" -> %>
                  <select name="value">
                    <option value="">—</option>
                    <option value="true" selected={@answers[q.id] == true}>Yes</option>
                    <option value="false" selected={@answers[q.id] == false}>No</option>
                  </select>
                <% "multi" -> %>
                  <input
                    type="text"
                    name="value"
                    placeholder="comma-separated"
                    value={format_multi(@answers[q.id])}
                  />
                <% _ -> %>
                  <input type="text" name="value" value={to_string(@answers[q.id] || "")} />
              <% end %>
              <button type="submit" class="btn btn-small">Save</button>
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
          prompt: q["prompt"] || q["text"] || q["id"],
          kind: q["kind"] || "text",
          domain: domain
        }
      end)
    end)
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
