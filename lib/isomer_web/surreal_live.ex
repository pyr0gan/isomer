defmodule IsomerWeb.SurrealLive do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use IsomerWeb, :live_view

      @impl true
      def terminate(_reason, socket) do
        case socket.assigns do
          %{surreal: conn} when not is_nil(conn) ->
            Isomer.Db.UserClient.stop(conn)

          _ ->
            :ok
        end

        :ok
      end
    end
  end
end
