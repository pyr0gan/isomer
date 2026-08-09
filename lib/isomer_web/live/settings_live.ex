defmodule IsomerWeb.SettingsLive do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user] || %{}
    prefs = GuideCopy.normalize(user)

    {:ok,
     assign(socket,
       page_title: "Settings",
       form: %{
         "name" => user["name"] || "",
         "self_role" => prefs["self_role"] || "",
         "experience_level" => prefs["experience_level"] || "",
         "comfort_level" => prefs["comfort_level"] || ""
       },
       error: nil,
       saved: false
     )}
  end

  @impl true
  def handle_event("save", params, socket) do
    attrs = %{
      "name" => Map.get(params, "name", ""),
      "self_role" => Map.get(params, "self_role", ""),
      "experience_level" => Map.get(params, "experience_level", ""),
      "comfort_level" => Map.get(params, "comfort_level", "")
    }

    case Tenant.update_user_prefs(socket.assigns.surreal, attrs) do
      {:ok, user} ->
        prefs = GuideCopy.normalize(user)

        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:guide_prefs, prefs)
         |> assign(:current_email, user["email"] || socket.assigns.current_email)
         |> assign(:form, %{
           "name" => user["name"] || "",
           "self_role" => prefs["self_role"] || "",
           "experience_level" => prefs["experience_level"] || "",
           "comfort_level" => prefs["comfort_level"] || ""
         })
         |> assign(:error, nil)
         |> assign(:saved, true)
         |> put_flash(
           :info,
           "Preferences saved — guidance copy will adapt on the next pages you open."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_error(reason), saved: false)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>Settings</.h1>
          <.p class="isomer-lede">{GuideCopy.settings_intro()}</.p>
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} />

      <form phx-submit="save" class="isomer-settings space-y-6">
        <.field
          type="text"
          name="name"
          label="Display name"
          value={@form["name"]}
          placeholder="How we should address you"
        />

        <div class="isomer-settings__group">
          <h2 class="isomer-settings__heading">How you approach this work</h2>
          <.p class="text-base text-slate-600 dark:text-slate-400">
            These choices only change the wording of tips and explanations — not which questions you see, and not a separate experience.
          </.p>

          <div class="isomer-settings__fields">
            <div class="isomer-settings__field">
              <label class="isomer-settings__label" for="self_role">Your role</label>
              <select id="self_role" name="self_role" class="wizard-domain-time__control">
                {Phoenix.HTML.Form.options_for_select(
                  [{"Not set", ""} | GuideCopy.role_options()],
                  @form["self_role"]
                )}
              </select>
            </div>

            <div class="isomer-settings__field">
              <label class="isomer-settings__label" for="experience_level">Experience level</label>
              <select id="experience_level" name="experience_level" class="wizard-domain-time__control">
                {Phoenix.HTML.Form.options_for_select(
                  [{"Not set", ""} | GuideCopy.experience_options()],
                  @form["experience_level"]
                )}
              </select>
            </div>

            <div class="isomer-settings__field">
              <label class="isomer-settings__label" for="comfort_level">
                Comfort with the material
              </label>
              <select id="comfort_level" name="comfort_level" class="wizard-domain-time__control">
                {Phoenix.HTML.Form.options_for_select(
                  [{"Not set", ""} | GuideCopy.comfort_options()],
                  @form["comfort_level"]
                )}
              </select>
            </div>
          </div>
        </div>

        <div class="isomer-form-actions">
          <.button type="submit" label="Save preferences" />
        </div>
      </form>
    </section>
    """
  end
end
