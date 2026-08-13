defmodule Isomer.Validate do
  @moduledoc "Corpus validator (port of tools/validate.py)."

  alias Isomer.Paths
  alias Isomer.Schema
  alias Isomer.YAML

  defstruct errors: [],
            warnings: [],
            req_ids: %{},
            question_count: 0,
            template_count: 0,
            seen_q: %{}

  def run(root \\ Isomer.root()) do
    root = Paths.expand_root!(root)
    {state, domain_ids} = load_domain_ids(%__MODULE__{}, root)

    state =
      state
      |> check_frameworks(root)
      |> check_requirements(root, domain_ids)
      |> check_mappings(root)
      |> check_rulesets(root)
      |> check_rubrics(root, domain_ids)
      |> check_questions(root, domain_ids)
      |> check_templates(root)

    report(state)
    if state.errors == [], do: :ok, else: :error
  end

  defp load_domain_ids(state, root) do
    path = Paths.join!(root, "vocab/domains.yaml")

    if File.exists?(path) do
      ids =
        path
        |> YAML.read!()
        |> Map.get("domains", [])
        |> Enum.map(& &1["id"])
        |> MapSet.new()

      {state, ids}
    else
      {add_error(state, "vocab/domains.yaml missing"), MapSet.new()}
    end
  end

  defp check_frameworks(state, root) do
    schema = Schema.load!("framework.schema.json")

    root
    |> Paths.wildcard!("frameworks/*/*/framework.yaml")
    |> Enum.reduce(state, fn path, st ->
      rel = Paths.relative!(path, root)
      doc = YAML.read!(path)
      st = schema_errors(st, schema, doc, rel)
      [_, fw, ver | _] = Path.split(rel)

      if doc["id"] != fw or to_string(doc["version"]) != ver do
        add_error(st, "#{rel}: framework id/version does not match directory (#{fw}/#{ver})")
      else
        st
      end
    end)
  end

  defp check_requirements(state, root, domain_ids) do
    schema = Schema.load!("requirement.schema.json")

    root
    |> Paths.wildcard!("frameworks/*/*/requirements/*.yaml")
    |> Enum.reduce(state, fn path, st ->
      rel = Paths.relative!(path, root)
      doc = YAML.read!(path)
      st = schema_errors(st, schema, doc, rel)
      rid = doc["id"] || ""

      st =
        case st.req_ids do
          %{^rid => other} ->
            add_error(st, "#{rel}: duplicate id #{rid} (also in #{other})")

          _ ->
            %{st | req_ids: Map.put(st.req_ids, rid, rel)}
        end

      parts = Path.split(rel)
      dir_fw = Enum.at(parts, 1)
      dir_ver = Enum.at(parts, 2)
      expected = "#{dir_fw}/#{dir_ver}/"

      st =
        if rid != "" and not String.starts_with?(rid, expected) do
          add_error(st, "#{rel}: id #{rid} does not match directory #{expected}")
        else
          st
        end

      st =
        if doc["framework"] != dir_fw or to_string(doc["framework_version"]) != dir_ver do
          add_error(st, "#{rel}: framework/framework_version fields disagree with directory")
        else
          st
        end

      st =
        if rid != "" and not String.ends_with?(rid, "/" <> to_string(doc["ref"])) do
          add_error(st, "#{rel}: id #{rid} does not end with ref #{doc["ref"]}")
        else
          st
        end

      st =
        Enum.reduce(doc["domains"] || [], st, fn d, acc ->
          if MapSet.size(domain_ids) > 0 and d not in domain_ids do
            add_error(acc, "#{rel}: unknown domain '#{d}'")
          else
            acc
          end
        end)

      if doc["type"] == "obligation" and not Map.has_key?(doc, "applicable_from") do
        add_error(st, "#{rel}: obligation missing applicable_from")
      else
        st
      end
    end)
  end

  defp check_mappings(state, root) do
    schema = Schema.load!("mapping.schema.json")

    root
    |> Paths.wildcard!("mappings/*.yaml")
    |> Enum.reduce(state, fn path, st ->
      rel = Paths.relative!(path, root)
      doc = YAML.read!(path)
      st = schema_errors(st, schema, doc, rel)

      Enum.with_index(doc["mappings"] || [])
      |> Enum.reduce(st, fn {m, i}, acc ->
        acc =
          Enum.reduce(["from", "to"], acc, fn end_key, a ->
            target = m[end_key] || ""

            if target != "" and not Map.has_key?(a.req_ids, target) do
              add_error(a, "#{rel}: mappings[#{i}].#{end_key} unresolved: #{target}")
            else
              a
            end
          end)

        if m["relation"] in ["partially_satisfied_by", "conflicts"] and blank?(m["note"]) do
          add_error(acc, "#{rel}: mappings[#{i}] relation '#{m["relation"]}' requires a note")
        else
          acc
        end
      end)
    end)
  end

  defp check_rulesets(state, root) do
    schema = Schema.load!("ruleset.schema.json")

    root
    |> Paths.wildcard!("rulesets/*.yaml")
    |> Enum.reduce(state, fn path, st ->
      rel = Paths.relative!(path, root)
      doc = YAML.read!(path)
      st = schema_errors(st, schema, doc, rel)
      fw = doc["framework"] || ""
      q_ids = MapSet.new(for q <- doc["questions"] || [], do: q["id"])

      Enum.with_index(doc["outcomes"] || [])
      |> Enum.reduce(st, fn {o, i}, acc ->
        acc =
          Enum.reduce(Map.keys(o["when"] || %{}), acc, fn qid, a ->
            if qid in q_ids do
              a
            else
              add_error(a, "#{rel}: outcomes[#{i}].when references unknown question '#{qid}'")
            end
          end)

        Enum.reduce(o["activates"] || [], acc, fn ref, a ->
          full = "#{fw}/#{ref}"

          if map_size(a.req_ids) > 0 and not Map.has_key?(a.req_ids, full) do
            add_warning(a, "#{rel}: outcomes[#{i}] activates '#{ref}' — #{full} not yet authored")
          else
            a
          end
        end)
      end)
    end)
  end

  defp check_rubrics(state, root, domain_ids) do
    schema = Schema.load!("rubric.schema.json")

    {state, rubric_domains} =
      root
      |> Paths.wildcard!("rubrics/*.yaml")
      |> Enum.reduce({state, MapSet.new()}, fn path, {st, seen} ->
        rel = Paths.relative!(path, root)
        doc = YAML.read!(path)
        st = schema_errors(st, schema, doc, rel)
        dom = doc["domain"] || ""

        st =
          if MapSet.size(domain_ids) > 0 and dom not in domain_ids do
            add_error(st, "#{rel}: unknown domain '#{dom}'")
          else
            st
          end

        st =
          if dom in seen do
            add_error(st, "#{rel}: duplicate rubric for domain '#{dom}'")
          else
            st
          end

        st =
          if Path.basename(path) != "#{dom}.yaml" do
            add_error(st, "#{rel}: filename does not match domain '#{dom}'")
          else
            st
          end

        lvls = for l <- doc["levels"] || [], do: l["level"]

        st =
          if lvls != ["L0", "L1", "L2", "L3", "L4"] do
            add_error(st, "#{rel}: levels must be exactly L0..L4 in order, got #{inspect(lvls)}")
          else
            st
          end

        {st, MapSet.put(seen, dom)}
      end)

    if MapSet.size(rubric_domains) > 0 and MapSet.size(domain_ids) > 0 do
      Enum.reduce(MapSet.difference(domain_ids, rubric_domains), state, fn missing, st ->
        add_warning(st, "rubrics: no rubric authored for domain '#{missing}'")
      end)
    else
      state
    end
  end

  defp check_questions(state, root, domain_ids) do
    schema = Schema.load!("question.schema.json")

    root
    |> Paths.wildcard!("questions/*.yaml")
    |> Enum.reduce(%{state | question_count: 0}, fn path, st ->
      rel = Paths.relative!(path, root)
      doc = YAML.read!(path)
      st = schema_errors(st, schema, doc, rel)
      dom = doc["domain"] || ""

      st =
        if MapSet.size(domain_ids) > 0 and dom not in domain_ids do
          add_error(st, "#{rel}: unknown domain '#{dom}'")
        else
          st
        end

      st =
        if Path.basename(path) != "#{dom}.yaml" do
          add_error(st, "#{rel}: filename does not match domain '#{dom}'")
        else
          st
        end

      Enum.reduce(doc["questions"] || [], st, fn q, acc ->
        acc = %{acc | question_count: acc.question_count + 1}
        qid = q["id"] || ""

        acc =
          case acc.seen_q do
            %{^qid => other} ->
              add_error(acc, "#{rel}: duplicate question id #{qid} (also in #{other})")

            _ ->
              %{acc | seen_q: Map.put(acc.seen_q, qid, rel)}
          end

        Enum.reduce(q["requirements"] || [], acc, fn rid, a ->
          if map_size(a.req_ids) > 0 and not Map.has_key?(a.req_ids, rid) do
            add_error(a, "#{rel}: question #{qid} references unresolved requirement #{rid}")
          else
            a
          end
        end)
      end)
    end)
  end

  defp check_templates(state, root) do
    schema = Schema.load!("template.schema.json")

    root
    |> Paths.wildcard!("templates/*.md")
    |> Enum.reduce(%{state | template_count: 0}, fn path, st ->
      rel = Paths.relative!(path, root)
      st = %{st | template_count: st.template_count + 1}
      text = File.read!(path)

      if not String.starts_with?(text, "---\n") do
        add_error(st, "#{rel}: missing YAML frontmatter")
      else
        case String.split(String.slice(text, 4..-1//1), "\n---\n", parts: 2) do
          [fm_text, body] ->
            fm =
              fm_text
              |> YamlElixir.read_from_string!()
              |> YAML.normalize()

            st = schema_errors(st, schema, fm, rel)

            st =
              if fm["id"] && Path.basename(path) != "#{fm["id"]}.md" do
                add_error(st, "#{rel}: filename does not match template id '#{fm["id"]}'")
              else
                st
              end

            st =
              Enum.reduce(fm["covers"] || [], st, fn rid, a ->
                if map_size(a.req_ids) > 0 and not Map.has_key?(a.req_ids, rid) do
                  add_error(a, "#{rel}: covers unresolved requirement #{rid}")
                else
                  a
                end
              end)

            Enum.reduce(fm["merge_fields"] || [], st, fn field, a ->
              if String.contains?(body, "{{" <> field <> "}}") do
                a
              else
                add_warning(a, "#{rel}: merge field '#{field}' declared but not used in body")
              end
            end)

          _ ->
            add_error(st, "#{rel}: frontmatter parse error: unterminated frontmatter")
        end
      end
    end)
  end

  defp schema_errors(state, schema, doc, rel) do
    Enum.reduce(Schema.validate(schema, doc), state, fn msg, st ->
      add_error(st, "#{rel}: schema: #{msg}")
    end)
  end

  defp report(state) do
    IO.puts("requirements: #{map_size(state.req_ids)}")
    IO.puts("questions: #{state.question_count}")
    IO.puts("templates: #{state.template_count}")
    Enum.each(state.warnings, &IO.puts("WARN  #{&1}"))
    Enum.each(state.errors, &IO.puts("ERROR #{&1}"))
    IO.puts("#{length(state.errors)} error(s), #{length(state.warnings)} warning(s)")
  end

  defp add_error(state, msg), do: %{state | errors: state.errors ++ [msg]}
  defp add_warning(state, msg), do: %{state | warnings: state.warnings ++ [msg]}
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
