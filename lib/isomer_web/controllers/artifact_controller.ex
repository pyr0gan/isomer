defmodule IsomerWeb.ArtifactController do
  use IsomerWeb, :controller

  alias Isomer.Artifacts.Render
  alias Isomer.Db.Tenant
  alias Isomer.Db.UserClient

  def download(conn, %{"id" => id} = params) do
    format = params |> Map.get("format", "markdown") |> to_string() |> String.downcase()
    token = conn.assigns[:surreal_token]
    id = Tenant.canonicalize_record_id(id)

    with true <- is_binary(token) and token != "",
         {:ok, client} <- UserClient.connect_with_token(token),
         {:ok, artifact} <- Tenant.get_artifact(client, id) do
      UserClient.stop(client)
      send_artifact(conn, artifact, format)
    else
      false ->
        conn
        |> put_flash(:error, "Sign in to download artifacts.")
        |> redirect(to: ~p"/login")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Artifact not found.")
        |> redirect(to: ~p"/library")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not download artifact.")
        |> redirect(to: ~p"/library")
    end
  end

  defp send_artifact(conn, artifact, format) when format in ["md", "markdown"] do
    stem = Render.filename_stem(artifact["title"] || artifact["template_id"] || "artifact")
    body = artifact["body"] || ""

    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{stem}.md"))
    |> send_resp(200, body)
  end

  defp send_artifact(conn, artifact, format) when format in ["pdf", "html"] do
    stem = Render.filename_stem(artifact["title"] || artifact["template_id"] || "artifact")
    title = artifact["title"] || "Artifact"
    # Print-ready HTML: pdf opens inline and nudges Print → Save as PDF.
    # No headless Chrome on the dyno.
    autoprint? = format == "pdf"
    html = Render.to_printable_html(artifact["body"] || "", title, autoprint: autoprint?)
    disposition = if autoprint?, do: "inline", else: "attachment"

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(#{disposition}; filename="#{stem}.html"))
    |> send_resp(200, html)
  end

  defp send_artifact(conn, _artifact, _format) do
    conn
    |> put_flash(:error, "Unsupported format. Use markdown or pdf.")
    |> redirect(to: ~p"/library")
  end
end
