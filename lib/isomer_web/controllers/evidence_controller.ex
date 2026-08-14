defmodule IsomerWeb.EvidenceController do
  use IsomerWeb, :controller

  alias Isomer.Db.Tenant
  alias Isomer.Db.UserClient
  alias Isomer.Evidence.Storage

  def download(conn, %{"id" => id}) do
    token = conn.assigns[:surreal_token]
    id = Tenant.canonicalize_record_id(id)

    with true <- is_binary(token) and token != "",
         {:ok, client} <- UserClient.connect_with_token(token),
         {:ok, evidence} <- Tenant.get_evidence(client, id) do
      UserClient.stop(client)
      send_evidence(conn, evidence)
    else
      false ->
        conn
        |> put_flash(:error, "Sign in to download evidence.")
        |> redirect(to: ~p"/login")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> text("Evidence not found.")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not download evidence.")
        |> redirect(to: ~p"/orgs")
    end
  end

  defp send_evidence(conn, evidence) do
    key = evidence["storage_key"]

    cond do
      is_binary(key) and String.starts_with?(key, "http://") ->
        redirect(conn, external: key)

      is_binary(key) and String.starts_with?(key, "https://") ->
        redirect(conn, external: key)

      Storage.object_key?(key) ->
        case Storage.get(key) do
          {:ok, body, meta} ->
            content_type =
              evidence["content_type"] || meta["content_type"] || "application/octet-stream"

            filename = download_name(evidence)

            conn
            |> put_resp_content_type(content_type)
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, body)

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> text("Evidence object not found in storage.")

          {:error, _} ->
            conn
            |> put_status(:bad_gateway)
            |> text("Could not read evidence object.")
        end

      true ->
        conn
        |> put_status(:not_found)
        |> text("This evidence has no downloadable object.")
    end
  end

  defp download_name(evidence) do
    label =
      evidence
      |> Map.get("label", "evidence")
      |> to_string()
      |> String.replace(~r/[^A-Za-z0-9._-]+/, "_")
      |> String.slice(0, 80)

    if label == "", do: "evidence.bin", else: label
  end
end
