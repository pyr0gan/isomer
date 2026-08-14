defmodule IsomerWeb.OrgLive.Members do
  use IsomerWeb.SurrealLive

  alias Isomer.Db.Tenant
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

      {:forbidden, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Only owners and admins can manage members.")
         |> push_navigate(to: ~p"/orgs/#{org_id}")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found")
         |> push_navigate(to: ~p"/orgs")}
    end
  end

  @impl true
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
         {:ok, membership} <- Tenant.get_membership(surreal, org_id) do
      role = Roles.normalize(membership["role"])

      if Roles.can_manage_members?(role) do
        members =
          case Tenant.list_members(surreal, org_id) do
            {:ok, rows} -> rows
            {:error, _} -> []
          end

        {:ok,
         %{
           page_title: "Members · #{org["name"]}",
           org: org,
           org_id: org_id,
           current_role: role,
           members: members,
           nav_org_id: org_id,
           nav_show_members: true
         }}
      else
        {:forbidden, org_id}
      end
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

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="isomer-page">
      <div class="isomer-page-header">
        <div>
          <.h1>Members</.h1>
          <.p class="isomer-lede">
            {@org["name"]} · add people who already have an isomer account.
            They must sign up before you can invite them by email.
          </.p>
        </div>
        <div class="flex flex-wrap gap-2">
          <.button
            link_type="live_redirect"
            to={~p"/orgs/#{@org_id}"}
            color="gray"
            variant="ghost"
            label="Org"
            icon="hero-arrow-left"
          />
        </div>
      </div>

      <.alert :if={@error} color="danger" variant="soft" with_icon label={@error} class="mb-4" />

      <.card>
        <.card_header title="People" description="Owners and admins can change roles and remove access." />
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
                <tr :if={@members == []}>
                  <td colspan="3" class="py-6 text-slate-500">No members listed yet.</td>
                </tr>
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
    </section>
    """
  end
end
