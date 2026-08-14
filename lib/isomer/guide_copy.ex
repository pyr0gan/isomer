defmodule Isomer.GuideCopy do
  @moduledoc """
  Adaptive guidance copy for non-expert (and expert) assessors.

  Presentation stays the same LiveView surfaces; only wording density and
  helper text change based on the signed-in user's self-identified role,
  experience, and comfort. Prefs live on the Surreal `user` record.
  """

  @roles ~w(executive product engineering compliance security operations other)
  @experience_levels ~w(beginner intermediate practitioner expert)
  @comfort_levels ~w(low moderate high)

  @type prefs :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  def roles, do: @roles
  def experience_levels, do: @experience_levels
  def comfort_levels, do: @comfort_levels

  def role_label("executive"), do: "Executive / leadership"
  def role_label("product"), do: "Product / program"
  def role_label("engineering"), do: "Engineering / ML"
  def role_label("compliance"), do: "Compliance / legal"
  def role_label("security"), do: "Security / risk"
  def role_label("operations"), do: "Operations / IT"
  def role_label("other"), do: "Other"
  def role_label(_), do: "Not set"

  def experience_label("beginner"), do: "New to this material"
  def experience_label("intermediate"), do: "Some familiarity"
  def experience_label("practitioner"), do: "Regular practitioner"
  def experience_label("expert"), do: "Deep expertise"
  def experience_label(_), do: "Not set"

  def comfort_label("low"), do: "Prefer plain-language help"
  def comfort_label("moderate"), do: "Balanced detail"
  def comfort_label("high"), do: "Keep it concise"
  def comfort_label(_), do: "Not set"

  def role_options, do: Enum.map(@roles, &{role_label(&1), &1})
  def experience_options, do: Enum.map(@experience_levels, &{experience_label(&1), &1})
  def comfort_options, do: Enum.map(@comfort_levels, &{comfort_label(&1), &1})

  @doc "Normalize a user row (or empty map) into string-keyed prefs."
  def normalize(nil), do: default_prefs()

  def normalize(user) when is_map(user) do
    %{
      "self_role" => pick(user, "self_role", @roles),
      "experience_level" => pick(user, "experience_level", @experience_levels),
      "comfort_level" => pick(user, "comfort_level", @comfort_levels)
    }
  end

  def default_prefs do
    %{
      "self_role" => nil,
      "experience_level" => nil,
      "comfort_level" => nil
    }
  end

  @doc """
  Overlay session-backed prefs onto Surreal (or other) prefs.

  Only non-nil overlay values win. Session maps that omit keys or carry
  explicit nils must not wipe values already stored on the user record —
  that pattern cleared settings across reload when the cookie fallback was
  empty or partial while Surreal still had prefs (or the reverse).
  """
  def overlay_prefs(base, overlay) do
    base = normalize(base)
    overlay = normalize(overlay || %{})

    Enum.reduce(~w(self_role experience_level comfort_level), base, fn key, acc ->
      case Map.get(overlay, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  @doc "True when the UI should show expanded plain-language help."
  def guided?(prefs) do
    prefs = normalize(prefs)

    prefs["experience_level"] in [nil, "beginner", "intermediate"] or
      prefs["comfort_level"] in [nil, "low", "moderate"]
  end

  @doc "True when copy should stay short (practitioners who opted for concise)."
  def concise?(prefs) do
    prefs = normalize(prefs)

    prefs["experience_level"] in ["practitioner", "expert"] and
      prefs["comfort_level"] == "high"
  end

  def wizard_lede(prefs, finalized?) do
    prefs = normalize(prefs)

    cond do
      finalized? ->
        "This run is finalized. You can review answers, or reopen it from Details if something needs changing."

      concise?(prefs) ->
        "Work domain by domain. Answers save as you go."

      guided?(prefs) ->
        role_bit = role_lede_bit(prefs["self_role"])

        "Take it one domain at a time — there is no single “right” pace. " <>
          "Answer what you know; leave the rest open and come back. " <>
          role_bit <>
          "Each save stores your response securely for this organization."

      true ->
        "Work domain by domain. Each answer is saved as you go."
    end
  end

  def settings_intro do
    "Tell us how you approach this material so prompts stay clear without changing the workflow. " <>
      "You can update these any time as you get more comfortable."
  end

  def library_intro(prefs) do
    if guided?(prefs) do
      "Templates are starting points for policies and registers. " <>
        "Open an assessment → Generate documents to fill a draft, then download Markdown or print to PDF from here."
    else
      "Corpus templates and drafts generated from each assessment’s Generate documents page."
    end
  end

  def artifacts_intro(prefs) do
    if guided?(prefs) do
      "This is where documents for this assessment are created. " <>
        "Pick a template, fill any merge fields you know, and generate a draft. " <>
        "You can regenerate later — earlier drafts stay listed until you delete them."
    else
      "Document generation for this assessment — templates use the organization context below."
    end
  end

  def artifacts_nav_label, do: "Generate documents"

  def artifacts_finalize_hint(prefs) do
    if guided?(prefs) do
      "Answers are locked. Next step: generate policy or register drafts for this assessment."
    else
      "Finalized — generate documents from this assessment when ready."
    end
  end

  def library_empty_artifacts(prefs) do
    if guided?(prefs) do
      "No drafts yet. Open an assessment, then use Generate documents (header button or Menu)."
    else
      "No drafts yet — generate from an assessment’s Generate documents page."
    end
  end

  def question_help(prefs, question) when is_map(question) do
    prefs = normalize(prefs)

    if concise?(prefs) do
      nil
    else
      level = Map.get(question, :level) || Map.get(question, "level")
      base = level_help(level)

      case prefs["self_role"] do
        "executive" ->
          join_help(
            base,
            "Focus on whether ownership and approval are clear — details can come from your team."
          )

        "engineering" ->
          join_help(
            base,
            "Think about how this shows up in design reviews, pipelines, and runbooks."
          )

        "compliance" ->
          join_help(base, "Look for dated approvals, versioned docs, and an audit trail.")

        "security" ->
          join_help(
            base,
            "Consider residual risk, control owners, and how you would evidence this to an auditor."
          )

        _ ->
          base
      end
    end
  end

  def evidence_help_text(prefs, prompt) do
    prefs = normalize(prefs)
    prompt = blank_to_nil(prompt)

    sufficiency =
      "Attach a label plus URL or reference below — a filename or ticket link is enough."

    cond do
      concise?(prefs) ->
        prompt

      is_binary(prompt) ->
        prompt <> " " <> sufficiency

      guided?(prefs) ->
        sufficiency

      true ->
        prompt
    end
  end

  @doc """
  Explains the wizard Time scale selector.

  Time scale is a relative effort rating for the domain on this assessment
  (not a calendar period). Hours are an optional clocked estimate. Neither
  field affects scoring.
  """
  def time_scale_help(prefs) do
    if concise?(prefs) do
      "Relative effort for this domain on this assessment, not a calendar period. " <>
        "Hours (optional) feed the org Time logged chart. Neither changes scores."
    else
      "Time scale is a relative effort rating for this domain on this assessment — " <>
        "not a date range or reporting period. Choose Low for a light touch, " <>
        "Medium for a meaningful block of work, or High if this domain was a major focus. " <>
        "Hours is an optional clocked estimate; it feeds the organization Time logged sparkline. " <>
        "Neither field affects maturity scores or questionnaire answers."
    end
  end

  @doc "Short explanation of Time scale / hours on the org Objective metrics panel."
  def org_time_scale_help(prefs) do
    if concise?(prefs) do
      "Low / Medium / High is relative effort per opted-in domain. Hours feed Time logged."
    else
      "Time scale (Low / Medium / High) is relative effort for each opted-in domain — " <>
        "not a calendar period. Hours feed the Time logged sparkline. " <>
        "Neither changes maturity scores."
    end
  end

  def merge_field_hint(prefs, field) when is_binary(field) do
    if guided?(prefs) do
      case field do
        "org.name" -> "Your organization display name."
        "org.exec_sponsor" -> "Named executive accountable for AI (or “TBD”)."
        "org.governance_lead" -> "Day-to-day governance lead (or “TBD”)."
        "policy.effective_date" -> "Date the policy takes effect (YYYY-MM-DD)."
        "policy.review_cadence" -> "How often you review (e.g. annually)."
        "soa.approval_date" -> "Date the Statement of Applicability was approved."
        "soa.approver" -> "Who approved the SoA."
        "soa.content_release" -> "Corpus or content edition label, if you track one."
        "register.last_updated" -> "When the system register was last reviewed."
        "system.name" -> "AI system or use-case name."
        "system.owner" -> "System owner."
        "assessment.date" -> "Assessment date (YYYY-MM-DD)."
        "assessment.assessor" -> "Who performed the assessment."
        "assessment.trigger" -> "Why this assessment ran (new system, change, periodic review)."
        _ -> "Used where the template shows {{#{field}}}."
      end
    else
      "{{#{field}}}"
    end
  end

  defp role_lede_bit("executive"),
    do: "As a leader, you can answer directionally and ask owners to attach evidence later. "

  defp role_lede_bit("engineering"),
    do: "Technical detail helps — but a clear Yes/No with a pointer to a repo or ticket is fine. "

  defp role_lede_bit("compliance"),
    do: "Prefer answers you can evidence; leave open anything still under review. "

  defp role_lede_bit("security"),
    do: "Call out gaps honestly — unanswered is better than an optimistic Yes. "

  defp role_lede_bit(_), do: ""

  defp level_help("L1"),
    do: "Foundational — a basic, documented practice is enough."

  defp level_help("L2"),
    do: "Established — look for repeatable process, not a one-off."

  defp level_help("L3"),
    do: "Managed — expect measurement, owners, and regular review."

  defp level_help("L4"),
    do: "Optimizing — continuous improvement and organization-wide learning."

  defp level_help(_), do: nil

  defp join_help(nil, extra), do: extra
  defp join_help(base, extra), do: base <> " " <> extra

  defp pick(user, key, allowed) do
    value = Map.get(user, key) || Map.get(user, String.to_atom(key))

    if is_binary(value) and value in allowed do
      value
    else
      nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_), do: nil
end
