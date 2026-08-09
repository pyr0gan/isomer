defmodule IsomerWeb.AssessmentLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Tenant.get_assessment(socket.assigns.surreal, id) do
      {:ok, assessment} ->
        org_id = Tenant.record_id(assessment["org"])

        {:ok,
         assign(socket,
           page_title: assessment["title"],
           assessment: assessment,
           assessment_id: id,
           org_id: org_id
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Assessment not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <div class="row">
        <h1>{@assessment["title"]}</h1>
        <.link navigate={~p"/assessments/#{@assessment_id}/q"} class="btn">Open wizard</.link>
      </div>
      <p class="lede">
        Status: <strong>{@assessment["status"]}</strong>
        · Kind: {@assessment["kind"]}
      </p>
      <p>
        Domains: {Enum.join(@assessment["domains"] || [], ", ")}
      </p>
      <.link navigate={~p"/orgs/#{@org_id}"}>← Back to org</.link>
    </section>
    """
  end
end
