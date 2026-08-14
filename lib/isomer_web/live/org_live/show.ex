defmodule IsomerWeb.OrgLive.Show do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant
  alias Isomer.GuideCopy
  alias Isomer.Maturity
  alias Isomer.OrgMetrics
  alias Isomer.Roles

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    org_id = Tenant.canonicalize_record_id(org_id)

    case load_state(socket.assigns.surreal, org_id) do
      {:ok, state} ->
        {:ok,
         assign(
           socket,
           Map.merge(state, %{error: nil, invite_email: "", invite_role: "assessor"})
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    if Roles.can_delete_org?(socket.assigns.current_role) do
      case Tenant.delete_org(socket.assigns.surreal, socket.assigns.org_id) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Organization deleted")
           |> push_navigate(to: ~p"/orgs")}

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    else
      {:noreply, assign(socket, error: "Only the organization owner can delete it.")}
    end
  end

  def handle_event("invite_member", params, socket) do
    if Roles.can_manage_members?(socket.assigns.current_role) do
      email = Map.get(params, "email", "")
      role = Map.get(params, "role", "assessor")

      case Tenant.add_member_by_email(
             socket.assigns.surreal,
             socket.assigns.org_id,
             email,
             role
           ) do
        {:ok, _row} ->
          case reload_members(socket) do
            {:ok, socket} ->
              {:noreply,
               socket
               |> assign(invite_email: "", invite_role: "assessor", error: nil)
               |> put_flash(:info, "Member added")}

            {:error, reason} ->
              {:noreply, assign(socket, error: format_error(reason))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    else
      {:noreply, assign(socket, error: "Only owners and admins can add members.")}
    end
  end

  def handle_event("update_member_role", %{"member_id" => member_id, "role" => role}, socket) do
    if Roles.can_manage_members?(socket.assigns.current_role) do
      case Tenant.update_member_role(
             socket.assigns.surreal,
             socket.assigns.org_id,
             member_id,
             role
           ) do
        {:ok, _row} ->
          case reload_members(socket) do
            {:ok, socket} ->
              {:noreply,
               socket
               |> assign(error: nil)
               |> put_flash(:info, "Role updated")}

            {:error, reason} ->
              {:noreply, assign(socket, error: format_error(reason))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    else
      {:noreply, assign(socket, error: "Only owners and admins can change roles.")}
    end
  end

  def handle_event("remove_member", %{"member_id" => member_id}, socket) do
    if Roles.can_manage_members?(socket.assigns.current_role) do
      case Tenant.remove_member(socket.assigns.surreal, socket.assigns.org_id, member_id) do
        :ok ->
          case reload_members(socket) do
            {:ok, socket} ->
              {:noreply,
               socket
               |> assign(error: nil)
               |> put_flash(:info, "Member removed")}

            {:error, reason} ->
              {:noreply, assign(socket, error: format_error(reason))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, error: format_error(reason))}
      end
    else
      {:noreply, assign(socket, error: "Only owners and admins can remove members.")}
    end
  end

  defp load_state(surreal, org_id) do
    with {:ok, org} <- Tenant.get_org(surreal, org_id),
         {:ok, membership} <- Tenant.get_membership(surreal, org_id),
         {:ok, assessments} <- Tenant.list_assessments(surreal, org_id) do
      role = Roles.normalize(membership["role"])

      members =
        if Roles.can_manage_members?(role) do
          case Tenant.list_members(surreal, org_id) do
            {:ok, rows} -> rows
            {:error, _} -> []
          end
        else
          []
        end

      maturity =
        case Maturity.org_domain_bars(surreal, assessments) do
          {:ok, bars} -> bars
          {:error, _} -> []
        end

      metrics =
        case OrgMetrics.org_panel(surreal, assessments) do
          {:ok, panel} -> panel
          {:error, _} -> empty_metrics()
        end

      {ongoing, finalized} = Enum.split_with(assessments, &ongoing?/1)

      {:ok,
       %{
         page_title: org["name"],
         org: org,
         org_id: org_id,
         current_role: role,
         membership: membership,
         members: members,
         assessments: assessments,
         ongoing_assessments: ongoing,
         finalized_assessments: finalized,
         maturity: maturity,
         metrics: metrics,
         nav_org_id: org_id
       }}
    end
  end

  defp reload_members(socket) do
    case Tenant.list_members(socket.assigns.surreal, socket.assigns.org_id) do
      {:ok, rows} ->
        {:ok, assign(socket, members: rows)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ongoing?(%{"status" => status}) when status in ["complete", "archived"], do: false
  defp ongoing?(_), do: true

  defp empty_metrics do
    %{
      "has_collection" => false,
      "current" => nil,
      "series" => %{
        "yes_pct" => [],
        "unanswered" => [],
        "evidence_pct" => [],
        "time_hours" => []
      }
    }
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
          <.h1>{@org["name"]}</.h1>
          <.p class="isomer-lede flex flex-wrap items-center gap-2">
            <.badge color="gray" variant="soft" label={Roles.label(@current_role)} />
            <span class="text-slate-500">
              {length(@assessments)} assessment(s) · id …{Tenant.short_key(@org_id)}
            </span>
          </.p>
        </div>
        <div class="flex flex-wrap gap-2">
          <.button
            :if={Roles.can_create_assessment?(@current_role)}
            link_type="live_redirect"
            to={~p"/orgs/#{@org_id}/assessments/new"}
            label="New assessment"
            icon="hero-plus"
          />
          <.button
            :if={Roles.can_delete_org?(@current_role)}
            type="button"
            color="danger"
            variant="outline"
            label="Delete org"
            phx-click="delete"
            data-confirm={"Delete “#{@org["name"]}” and all its assessments? This cannot be undone."}
          />
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} class="mb-4" />

      <%= if @assessments == [] do %>
        <.card class="mb-8">
          <.card_content class="space-y-4 py-10 text-center">
            <.h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">
              Start your first assessment
            </.h3>
            <.p no_margin class="mx-auto max-w-lg text-slate-600 dark:text-slate-400">
              Classify obligations, answer domain maturity questions, attach evidence, and generate governance drafts — all from one assessment run.
            </.p>
            <.button
              :if={Roles.can_create_assessment?(@current_role)}
              link_type="live_redirect"
              to={~p"/orgs/#{@org_id}/assessments/new"}
              label="Create assessment"
              icon="hero-plus"
              class="mt-2"
            />
            <.p :if={not Roles.can_create_assessment?(@current_role)} no_margin class="text-slate-500">
              You have viewer access. Ask an owner or admin to create an assessment or raise your role.
            </.p>
          </.card_content>
        </.card>
      <% else %>
        <div class="mb-10 space-y-8">
          <div>
            <.h3 class="mb-3">Ongoing</.h3>
            <%= if @ongoing_assessments == [] do %>
              <.p class="text-slate-500">
                No ongoing assessments.
                <.link
                  :if={Roles.can_create_assessment?(@current_role)}
                  navigate={~p"/orgs/#{@org_id}/assessments/new"}
                  class="font-medium underline underline-offset-2"
                >
                  Start one
                </.link>
              </.p>
            <% else %>
              <.assessment_list
                assessments={@ongoing_assessments}
                can_write={Roles.can_write?(@current_role)}
              />
            <% end %>
          </div>

          <div>
            <.h3 class="mb-3">Finalized</.h3>
            <%= if @finalized_assessments == [] do %>
              <.p class="text-slate-500">No finalized assessments yet.</.p>
            <% else %>
              <.assessment_list
                assessments={@finalized_assessments}
                can_write={Roles.can_write?(@current_role)}
              />
            <% end %>
          </div>
        </div>
      <% end %>

      <.card :if={Roles.can_manage_members?(@current_role)} class="mb-8">
        <.card_header
          title="Members"
          description="Add people who already have an isomer account. They must sign up before you can invite them by email."
        />
        <.card_content class="space-y-6">
          <form phx-submit="invite_member" class="flex flex-wrap items-end gap-3">
            <.field
              type="email"
              name="email"
              label="Email"
              value={@invite_email}
              placeholder="colleague@example.com"
              required
              no_margin
              wrapper_class="min-w-[16rem] flex-1"
            />
            <div class="answer-select min-w-[10rem]">
              <label class="answer-select__label" for="invite-role">Role</label>
              <select id="invite-role" name="role" class="answer-select__control">
                {Phoenix.HTML.Form.options_for_select(Roles.invite_options(), @invite_role)}
              </select>
            </div>
            <.button type="submit" size="sm" label="Add member" icon="hero-user-plus" />
          </form>

          <div class="overflow-x-auto">
            <table class="min-w-full text-left text-sm">
              <thead class="border-b border-slate-200 text-slate-500 dark:border-slate-700">
                <tr>
                  <th class="py-2 pr-4 font-medium">Person</th>
                  <th class="py-2 pr-4 font-medium">Role</th>
                  <th class="py-2 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={m <- @members}
                  class="border-b border-slate-100 dark:border-slate-800"
                >
                  <td class="py-2.5 pr-4">
                    <span class="font-medium text-slate-800 dark:text-slate-200">
                      {m["email"] || "—"}
                    </span>
                    <span
                      :if={m["name"] not in [nil, ""]}
                      class="mt-0.5 block text-slate-500"
                    >
                      {m["name"]}
                    </span>
                  </td>
                  <td class="py-2.5 pr-4">
                    <form phx-change="update_member_role" class="inline">
                      <input type="hidden" name="member_id" value={m["id"]} />
                      <select
                        name="role"
                        class="answer-select__control"
                        id={"member-role-#{m["id"]}"}
                      >
                        {Phoenix.HTML.Form.options_for_select(Roles.options(), m["role"])}
                      </select>
                    </form>
                  </td>
                  <td class="py-2.5 text-right">
                    <.button
                      type="button"
                      size="sm"
                      color="danger"
                      variant="ghost"
                      label="Remove"
                      phx-click="remove_member"
                      phx-value-member_id={m["id"]}
                      data-confirm={"Remove #{m["email"] || "this member"} from the organization?"}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card_content>
      </.card>

      <.p
        :if={not Roles.can_manage_members?(@current_role)}
        class="mb-8 text-sm text-slate-500"
      >
        Your role on this org is <span class="font-medium">{Roles.label(@current_role)}</span>.
        Member administration is limited to owners and admins.
      </.p>

      <details class="group mb-4 rounded-lg border border-slate-200 open:pb-0 dark:border-slate-700">
        <summary class="cursor-pointer list-none px-4 py-3 font-medium text-slate-800 dark:text-slate-200 marker:content-none">
          <span class="inline-flex items-center gap-2">
            Maturity & metrics
            <span class="text-sm font-normal text-slate-500">
              (secondary — expands when you want the charts)
            </span>
          </span>
        </summary>
        <div class="maturity-panels border-t border-slate-200 px-4 py-4 dark:border-slate-700">
          <.card class="maturity-card">
            <.card_header
              title="Org maturity"
              description="Estimated from Yes answers on L1/L2 questions (newest assessment wins)."
            />
            <.card_content>
              <%= if @maturity == [] do %>
                <.p no_margin class="text-base text-slate-500 dark:text-slate-400">
                  No domain maturity yet — complete assessment questions to estimate levels.
                </.p>
              <% else %>
                <div class="maturity-chart" role="img" aria-label="Domain maturity levels">
                  <div :for={bar <- @maturity} class="maturity-row">
                    <span class="maturity-row__label">{bar["label"]}</span>
                    <div
                      class="maturity-row__track"
                      title={"#{bar["answered"]}/#{bar["total"]} met"}
                    >
                      <div
                        class={"maturity-row__fill maturity-row__fill--#{bar["level"]}"}
                        style={"width: #{bar["pct"]}%"}
                      >
                      </div>
                    </div>
                    <.tooltip
                      label={"#{bar["level_label"]} — #{bar["level_tip"]}"}
                      placement="top"
                    >
                      <.badge
                        color={bar["level_color"] || "primary"}
                        variant="soft"
                        label={bar["level_label"]}
                        class="maturity-row__level cursor-help"
                      />
                    </.tooltip>
                  </div>
                </div>
              <% end %>
            </.card_content>
          </.card>

          <.card class="metrics-card">
            <.card_header
              title="Objective metrics"
              description="Opted-in domains from assessment wizards (finalized and in progress)."
            />
            <.card_content>
              <%= if @metrics["has_collection"] do %>
                <div class="metrics-sparklines">
                  <.metric_sparkline
                    label="Yes answers"
                    suffix="%"
                    value={get_in(@metrics, ["current", "yes_pct"])}
                    series={@metrics["series"]["yes_pct"]}
                  />
                  <.metric_sparkline
                    label="Unanswered"
                    value={get_in(@metrics, ["current", "unanswered"])}
                    series={@metrics["series"]["unanswered"]}
                  />
                  <.metric_sparkline
                    label="Evidence coverage"
                    suffix="%"
                    value={get_in(@metrics, ["current", "evidence_pct"])}
                    series={@metrics["series"]["evidence_pct"]}
                  />
                  <.metric_sparkline
                    label="Time logged"
                    suffix="h"
                    value={get_in(@metrics, ["current", "time_hours_total"])}
                    series={@metrics["series"]["time_hours"]}
                  />
                </div>

                <div
                  :if={get_in(@metrics, ["current", "domains"]) not in [nil, []]}
                  class="metrics-domains"
                >
                  <p class="metrics-domains__title">Time by objective</p>
                  <ul class="metrics-domains__list">
                    <li
                      :for={row <- get_in(@metrics, ["current", "domains"]) || []}
                      class="metrics-domains__row"
                    >
                      <span class="metrics-domains__label">{row["label"]}</span>
                      <span class="metrics-domains__scale">{row["time_scale_label"]}</span>
                      <span class="metrics-domains__hours">{format_hours(row["hours"])}</span>
                    </li>
                  </ul>
                </div>
              <% else %>
                <.p no_margin class="text-base text-slate-500 dark:text-slate-400">
                  Mark domains for metric collection in an assessment wizard to populate this panel.
                </.p>
              <% end %>
            </.card_content>
          </.card>
        </div>
      </details>
    </section>
    """
  end

  attr(:assessments, :list, required: true)
  attr(:can_write, :boolean, default: true)

  defp assessment_list(assigns) do
    ~H"""
    <ul class="space-y-3">
      <li :for={a <- @assessments}>
        <.card class="transition hover:border-primary-300 hover:shadow-md">
          <.card_content class="flex flex-wrap items-center justify-between gap-3">
            <div class="min-w-0 flex-1 space-y-1">
              <.link navigate={~p"/assessments/#{a["id"]}"} class="no-underline">
                <span class="block font-mono text-base font-semibold text-slate-900 dark:text-slate-100">
                  {a["title"]}
                </span>
              </.link>
              <div class="flex flex-wrap items-center gap-2">
                <.badge
                  color={status_badge_color(a["status"])}
                  variant="soft"
                  label={status_label(a["status"])}
                />
                <.badge color="gray" variant="soft" label={a["kind"] || "domains"} />
                <.badge
                  :if={classification_label(a["classification"])}
                  color="info"
                  variant="soft"
                  label={classification_label(a["classification"])}
                />
                <span class="text-sm text-slate-500">
                  {domain_count(a)} domain(s)
                </span>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <.button
                link_type="live_redirect"
                to={~p"/assessments/#{a["id"]}"}
                color="gray"
                variant="ghost"
                size="sm"
                label="Details"
              />
              <.button
                link_type="live_redirect"
                to={~p"/assessments/#{a["id"]}/q"}
                color="gray"
                variant="outline"
                size="sm"
                label={if finalized?(a), do: "Wizard", else: if(@can_write, do: "Wizard", else: "View")}
                icon="hero-play"
              />
              <.button
                link_type="live_redirect"
                to={~p"/assessments/#{a["id"]}/results"}
                color="gray"
                variant="outline"
                size="sm"
                label="Results"
                icon="hero-chart-bar"
              />
              <.button
                link_type="live_redirect"
                to={~p"/assessments/#{a["id"]}/artifacts"}
                color="gray"
                variant="ghost"
                size="sm"
                label={GuideCopy.artifacts_nav_label()}
                icon="hero-document-text"
              />
            </div>
          </.card_content>
        </.card>
      </li>
    </ul>
    """
  end

  defp domain_count(%{"domains" => domains}) when is_list(domains), do: length(domains)
  defp domain_count(_), do: 0

  defp finalized?(%{"status" => status}) when status in ["complete", "archived"], do: true
  defp finalized?(_), do: false

  defp classification_label(%{"label" => label}) when is_binary(label) and label != "", do: label

  defp classification_label(%{"classification" => label})
       when is_binary(label) and label != "",
       do: label

  defp classification_label(_), do: nil

  defp format_hours(nil), do: "—"
  defp format_hours(hours) when is_number(hours), do: "#{Float.round(hours * 1.0, 1)}h"
  defp format_hours(_), do: "—"

  defp status_label(status) when status in ["complete", "archived"], do: "finalized"
  defp status_label(status) when is_binary(status) and status != "", do: status
  defp status_label(_), do: "draft"

  defp status_badge_color(status) when status in ["complete", "archived"], do: "success"
  defp status_badge_color("in_progress"), do: "primary"
  defp status_badge_color(_), do: "info"
end
