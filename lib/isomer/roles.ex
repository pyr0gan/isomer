defmodule Isomer.Roles do
  @moduledoc """
  Org membership roles (`member.role`) and projector authorization helpers.

  Surreal `PERMISSIONS` remain the enforcement boundary; these helpers only
  hide or soft-block write affordances in LiveView.
  """

  @roles ~w(owner admin assessor viewer)
  @write_roles ~w(owner admin assessor)
  @admin_roles ~w(owner admin)

  def all, do: @roles

  def write_roles, do: @write_roles

  def admin_roles, do: @admin_roles

  def valid?(role) when is_binary(role), do: role in @roles
  def valid?(_), do: false

  def label("owner"), do: "Owner"
  def label("admin"), do: "Admin"
  def label("assessor"), do: "Assessor"
  def label("viewer"), do: "Viewer"
  def label(_), do: "Unknown"

  def options do
    Enum.map(@roles, &{label(&1), &1})
  end

  def invite_options do
    # Owners are created with the org; invite flow offers the rest.
    Enum.map(~w(admin assessor viewer), &{label(&1), &1})
  end

  def can_manage_members?(role), do: role in @admin_roles

  def can_write?(role), do: role in @write_roles

  def can_delete_org?(role), do: role == "owner"

  def can_delete_assessment?(role), do: role in @admin_roles

  def can_create_assessment?(role), do: role in @write_roles

  @doc "Normalize a role string; unknown/blank becomes `viewer` (least privilege)."
  def normalize(role) when is_binary(role) do
    role = String.trim(role)
    if role in @roles, do: role, else: "viewer"
  end

  def normalize(_), do: "viewer"
end
