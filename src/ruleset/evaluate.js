/**
 * First-match classification ruleset evaluation.
 *
 * Outcome order is semantic: the first matching `outcomes[]` entry wins;
 * otherwise `default_outcome` applies. Do not reorder ruleset YAML casually.
 *
 * Effective-date precedence: outcome.applicable_from overrides each
 * activated requirement's applicable_from (which records the earliest
 * pathway). Same articles can bind on different dates by classification
 * (e.g. Annex III 2027-12-02 vs Annex I 2028-08-02).
 */

/**
 * @param {unknown} expected
 * @param {unknown} actual
 */
function answerMatches(expected, actual) {
  if (Array.isArray(expected)) {
    return expected.includes(actual);
  }
  if (typeof expected === "boolean") {
    return Boolean(actual) === expected;
  }
  return actual === expected;
}

/**
 * @param {Record<string, unknown>} when
 * @param {Record<string, unknown>} answers
 */
export function matchesWhen(when, answers) {
  for (const [qid, expected] of Object.entries(when || {})) {
    if (!answerMatches(expected, answers[qid])) return false;
  }
  return true;
}

/**
 * Pick the first matching outcome, or the default.
 *
 * @param {object} ruleset
 * @param {Record<string, unknown>} answers
 */
export function selectOutcome(ruleset, answers) {
  for (const outcome of ruleset.outcomes || []) {
    if (matchesWhen(outcome.when, answers)) {
      return { outcome, matched: "outcome", index: ruleset.outcomes.indexOf(outcome) };
    }
  }
  return { outcome: ruleset.default_outcome, matched: "default", index: null };
}

/**
 * Resolve activated obligation ids + effective dates for an answer set.
 *
 * @param {object} options
 * @param {object} options.ruleset Classification ruleset doc
 * @param {Record<string, unknown>} options.answers question id -> answer
 * @param {Map<string, object>|Record<string, object>} [options.requirementsById]
 *   Optional corpus requirements keyed by full id (`framework/version/ref`)
 *   for title + requirement-level applicable_from lookup.
 */
export function evaluateRuleset({ ruleset, answers, requirementsById = {} }) {
  const reqMap =
    requirementsById instanceof Map
      ? requirementsById
      : new Map(Object.entries(requirementsById));

  const { outcome, matched, index } = selectOutcome(ruleset, answers);
  if (!outcome) {
    throw new Error("Ruleset has no matching outcome and no default_outcome");
  }

  const framework = ruleset.framework;
  const outcomeDate = outcome.applicable_from ?? null;
  const activates = outcome.activates || [];

  const obligations = activates.map((ref) => {
    const id = `${framework}/${ref}`;
    const req = reqMap.get(id);
    const requirementDate = req?.applicable_from ?? null;
    // Outcome date wins when present; else fall back to requirement date.
    const applicableFrom = outcomeDate ?? requirementDate;
    return {
      ref,
      id,
      title: req?.title ?? null,
      applicable_from: applicableFrom,
      requirement_applicable_from: requirementDate,
      date_source: outcomeDate != null ? "outcome" : "requirement",
    };
  });

  return {
    ruleset: ruleset.ruleset,
    framework,
    classification: outcome.classification,
    matched,
    outcome_index: index,
    note: outcome.note ?? null,
    outcome_applicable_from: outcomeDate,
    activates: obligations,
  };
}
