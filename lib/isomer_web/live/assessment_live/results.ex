defmodule IsomerWeb.AssessmentLive.Results do
  use IsomerWeb.SurrealLive

  alias Isomer.AssessmentResults
  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy

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

  defp load_state(surreal, id) do
    with {:ok, assessment} <- Tenant.get_assessment(surreal, id),
         {:ok, answers} <- Tenant.list_answers(surreal, id),
         {:ok, sets} <- Tenant.list_question_sets(surreal) do
      activates =
        assessment
        |> Map.get("activates", [])
        |> List.wrap()
        |> Enum.map(&to_string/1)
        |> Enum.reject(&(&1 == ""))

      target_ids =
        sets
        |> Enum.flat_map(fn set ->
          Enum.flat_map(set["questions"] || [], fn q -> q["requirements"] || [] end)
        end)
        |> Enum.map(&to_string/1)

      req_ids = Enum.uniq(activates ++ target_ids)

      requirements =
        case Tenant.list_requirements_by_ids(surreal, req_ids) do
          {:ok, index} -> index
          {:error, _} -> %{}
        end

      edges =
        case Tenant.list_satisfier_edges(surreal, activates) do
          {:ok, rows} -> rows
          {:error, _} -> []
        end

      results =
        AssessmentResults.build(%{
          assessment: assessment,
          answers: questionnaire_answers(answers),
          question_sets: sets,
          requirements: requirements,
          satisfier_edges: edges
        })

      org_id = Tenant.canonicalize_record_id(assessment["org"])

      {:ok,
       %{
         page_title: "Results · #{assessment["title"]}",
         assessment: assessment,
         assessment_id: id,
         org_id: org_id,
         finalized: finalized?(assessment),
         results: results,
         nav_org_id: org_id,
         nav_assessment_id: id,
         nav_assessment_title: assessment["title"]
       }}
    end
  end

  # Exclude generated documents stored as answer rows.
  defp questionnaire_answers(rows) do
    Enum.reject(rows, fn row ->
      row["pack_ref"] == Tenant.artifact_pack_ref()
    end)
  end

  defp finalized?(%{"status" => status}) when status in ["complete", "archived"], do: true
  defp finalized?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>Results · {@assessment["title"]}</.h1>
          <.p class="isomer-lede flex flex-wrap items-center gap-2">
            <.badge
              color={status_badge_color(@assessment["status"])}
              variant="soft"
              label={status_label(@assessment["status"])}
            />
            <.badge color="gray" variant="soft" label={@assessment["kind"] || "domains"} />
            <.badge
              :if={@results["has_classification"]}
              color="info"
              variant="soft"
              label={@results["classification"]["label"]}
            />
          </.p>
          <.p class="text-slate-600 dark:text-slate-400">
            What applies, what mappings cover, and what is still open on this assessment.
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
            to={~p"/assessments/#{@assessment_id}/q"}
            color="gray"
            variant="outline"
            label={if @finalized, do: "View wizard", else: "Open wizard"}
            icon="hero-play"
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

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} class="mb-4" />

      <.alert
        :if={@finalized}
        color="success"
        variant="soft"
        with_icon
        class="mb-4"
        label="Assessment is finalized. Results reflect locked answers until you reopen it."
      />

      <.card :if={@assessment["ruleset_id"] not in [nil, ""]} class="mb-6">
        <.card_header title="Classification" />
        <.card_content class="space-y-3">
          <.p no_margin class="text-slate-700 dark:text-slate-300">
            Ruleset: <code class="text-sm">{@assessment["ruleset_id"]}</code>
          </.p>
          <%= if @results["has_classification"] do %>
            <.p no_margin class="text-slate-700 dark:text-slate-300">
              Outcome:
              <span class="font-medium">{@results["classification"]["label"]}</span>
            </.p>
            <.p
              :if={note = @results["classification"]["note"]}
              no_margin
              class="text-slate-600 dark:text-slate-400"
            >
              {note}
            </.p>
            <.p no_margin class="text-slate-600 dark:text-slate-400">
              {@results["obligation_summary"]["total"]} activated obligation(s) ·
              {@results["obligation_summary"]["covered"]} covered by mapping ·
              {@results["obligation_summary"]["partial"]} partial ·
              {@results["obligation_summary"]["open"]} without satisfaction mapping ·
              {@results["obligation_summary"]["untouched"]} still open in this assessment
            </.p>
          <% else %>
            <.p no_margin class="text-slate-500">
              Answer the classification questions in the
              <.link
                navigate={~p"/assessments/#{@assessment_id}/q"}
                class="font-medium underline underline-offset-2"
              >
                wizard
              </.link>
              to compute an outcome.
            </.p>
          <% end %>
        </.card_content>
      </.card>

      <.card :if={@results["obligations"] != []} class="mb-6">
        <.card_header title="Activated obligations & residual coverage" />
        <.card_content class="space-y-6">
          <div :for={ob <- @results["obligations"]} class="border-b border-slate-200 pb-5 last:border-0 last:pb-0 dark:border-slate-700">
            <div class="mb-2 flex flex-wrap items-start justify-between gap-2">
              <div>
                <.h3 class="text-base font-semibold text-slate-900 dark:text-slate-100">
                  {ob["short_id"]} — {ob["title"]}
                </.h3>
                <.p no_margin class="text-sm text-slate-500">{ob["corpus_id"]}</.p>
              </div>
              <div class="flex flex-wrap gap-2">
                <.badge
                  color={mapping_badge_color(ob["mapping_status"])}
                  variant="soft"
                  label={mapping_label(ob["mapping_status"])}
                />
                <.badge
                  color={progress_badge_color(ob["progress_status"])}
                  variant="soft"
                  label={progress_label(ob["progress_status"])}
                />
              </div>
            </div>

            <%= if ob["satisfiers"] == [] do %>
              <.p no_margin class="text-slate-600 dark:text-slate-400">
                No <code class="text-sm">satisfied_by</code> /
                <code class="text-sm">partially_satisfied_by</code> edges for this obligation —
                residual work until mappings or compensating controls are recorded.
              </.p>
            <% else %>
              <ul class="mt-3 space-y-3">
                <li
                  :for={s <- ob["satisfiers"]}
                  class="rounded-md bg-slate-50 px-3 py-2 dark:bg-slate-900/40"
                >
                  <div class="flex flex-wrap items-center gap-2">
                    <.badge
                      color={if s["relation"] == "satisfied_by", do: "success", else: "warning"}
                      variant="soft"
                      label={s["relation"]}
                    />
                    <span class="font-medium text-slate-800 dark:text-slate-200">
                      {s["target_title"]}
                    </span>
                    <span class="text-sm text-slate-500">{s["target_corpus_id"]}</span>
                    <.badge
                      :if={s["answered_yes"]}
                      color="success"
                      variant="soft"
                      label="Yes in assessment"
                    />
                    <.badge
                      :if={not s["answered_yes"] and s["question_ids"] != []}
                      color="gray"
                      variant="soft"
                      label="Not yet affirmed"
                    />
                    <.badge
                      :if={s["question_ids"] == []}
                      color="gray"
                      variant="soft"
                      label="No domain question"
                    />
                  </div>
                  <.p
                    :if={is_binary(s["note"]) and s["note"] != ""}
                    no_margin
                    class="mt-1 text-sm text-slate-600 dark:text-slate-400"
                  >
                    {s["note"]}
                  </.p>
                </li>
              </ul>
            <% end %>

            <ul :if={ob["gap_notes"] != []} class="mt-3 list-disc space-y-1 pl-5 text-sm text-amber-800 dark:text-amber-200">
              <li :for={gap <- ob["gap_notes"]}>Gap: {gap}</li>
            </ul>
          </div>
        </.card_content>
      </.card>

      <.card :if={@results["domains"] != []} class="mb-6">
        <.card_header title="Domain maturity & completion" />
        <.card_content class="space-y-4">
          <.p no_margin class="text-slate-600 dark:text-slate-400">
            {@results["domain_summary"]["answered"]} of {@results["domain_summary"]["total"]} questions answered ·
            {@results["domain_summary"]["unanswered"]} unanswered
            <%= if @results["domain_summary"]["yes_pct"] do %>
              · {@results["domain_summary"]["yes_pct"]}% Yes
            <% end %>
          </.p>

          <div class="overflow-x-auto">
            <table class="min-w-full text-left text-sm">
              <thead class="border-b border-slate-200 text-slate-500 dark:border-slate-700">
                <tr>
                  <th class="py-2 pr-4 font-medium">Domain</th>
                  <th class="py-2 pr-4 font-medium">Progress</th>
                  <th class="py-2 pr-4 font-medium">Yes</th>
                  <th class="py-2 font-medium">Est. level</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={d <- @results["domains"]}
                  class="border-b border-slate-100 dark:border-slate-800"
                >
                  <td class="py-2.5 pr-4 font-medium text-slate-800 dark:text-slate-200">
                    {d["label"]}
                  </td>
                  <td class="py-2.5 pr-4 text-slate-600 dark:text-slate-400">
                    {d["answered"]}/{d["total"]}
                    <span :if={d["unanswered"] > 0} class="text-slate-400">
                      ({d["unanswered"]} open)
                    </span>
                  </td>
                  <td class="py-2.5 pr-4 text-slate-600 dark:text-slate-400">
                    {d["yes"]}
                    <span :if={d["yes_pct"]}>({d["yes_pct"]}%)</span>
                  </td>
                  <td class="py-2.5">
                    <.badge color={d["level_color"]} variant="soft" label={d["level_label"]} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.p :if={@results["domain_summary"]["unanswered"] > 0} no_margin class="text-slate-500">
            Continue in the
            <.link
              navigate={~p"/assessments/#{@assessment_id}/q"}
              class="font-medium underline underline-offset-2"
            >
              wizard
            </.link>
            to close open questions.
          </.p>
        </.card_content>
      </.card>

      <.card
        :if={@results["obligations"] == [] and @results["domains"] == []}
        class="mb-6"
      >
        <.card_content>
          <.p no_margin class="text-slate-600 dark:text-slate-400">
            This assessment has no activated obligations and no domain packs yet.
            Add domains or complete classification in Details / the wizard.
          </.p>
        </.card_content>
      </.card>
    </section>
    """
  end

  defp status_label(status) when status in ["complete", "archived"], do: "finalized"
  defp status_label(status) when is_binary(status) and status != "", do: status
  defp status_label(_), do: "draft"

  defp status_badge_color(status) when status in ["complete", "archived"], do: "success"
  defp status_badge_color("in_progress"), do: "primary"
  defp status_badge_color(_), do: "info"

  defp mapping_label("covered"), do: "Mapping: covered"
  defp mapping_label("partial"), do: "Mapping: partial"
  defp mapping_label("open"), do: "Mapping: open"
  defp mapping_label(_), do: "Mapping: —"

  defp mapping_badge_color("covered"), do: "success"
  defp mapping_badge_color("partial"), do: "warning"
  defp mapping_badge_color(_), do: "danger"

  defp progress_label("addressed"), do: "Assessment: addressed"
  defp progress_label("partial"), do: "Assessment: partial"
  defp progress_label("untouched"), do: "Assessment: open"
  defp progress_label("unmapped"), do: "Assessment: unmapped"
  defp progress_label(_), do: "Assessment: —"

  defp progress_badge_color("addressed"), do: "success"
  defp progress_badge_color("partial"), do: "warning"
  defp progress_badge_color(_), do: "gray"
end
