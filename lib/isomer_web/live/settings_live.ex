defmodule IsomerWeb.SettingsLive do
  use IsomerWeb.SurrealLive

  alias Isomer.GuideCopy

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns[:current_user] || %{}
    prefs = socket.assigns[:guide_prefs] || GuideCopy.normalize(user)
    name = session["guide_name"] || user["name"] || ""

    {:ok,
     assign(socket,
       page_title: "Settings",
       form: %{
         "name" => name,
         "self_role" => prefs["self_role"] || "",
         "experience_level" => prefs["experience_level"] || "",
         "comfort_level" => prefs["comfort_level"] || ""
       },
       error: nil,
       saved: false
     )}
  end

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

      <form action={~p"/settings"} method="post" class="isomer-settings space-y-6">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
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
