defmodule Isomer.Artifacts.RenderTest do
  use ExUnit.Case, async: true

  alias Isomer.Artifacts.Render

  test "substitutes merge fields and blanks become em dash" do
    body = "# {{org.name}}\n\nOwner: {{org.exec_sponsor}}"
    out = Render.render(body, %{"org.name" => "Acme", "org.exec_sponsor" => ""})
    assert out =~ "# Acme"
    assert out =~ "Owner: —"
  end

  test "extract_fields preserves order and uniqueness" do
    body = "{{org.name}} then {{org.name}} and {{policy.effective_date}}"
    assert Render.extract_fields(body) == ["org.name", "policy.effective_date"]
  end

  test "build_values prefills org name and allows overrides" do
    values =
      Render.build_values(
        %{"name" => "Acme"},
        %{"title" => "Run"},
        %{"org.exec_sponsor" => "Ada"}
      )

    assert values["org.name"] == "Acme"
    assert values["org.exec_sponsor"] == "Ada"
    assert values["assessment.date"] =~ ~r/^\d{4}-\d{2}-\d{2}$/
  end

  test "to_printable_html escapes and wraps headings" do
    html = Render.to_printable_html("# Title\n\nHello **world** <script>", "Doc")
    assert html =~ "<h1>Title</h1>"
    assert html =~ "<strong>world</strong>"
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end

  test "filename_stem sanitizes titles" do
    assert Render.filename_stem("AI Policy (v1)") == "ai-policy-v1"
    assert Render.filename_stem("@@@") == "artifact"
  end
end
