defmodule TienLen.Admin.Action do
  @moduledoc "One line of the append-only admin audit log (AD2)."
  use Ecto.Schema

  schema "admin_actions" do
    belongs_to :admin, TienLen.Accounts.User
    belongs_to :target_user, TienLen.Accounts.User
    field :action, :string
    field :details, :map, default: %{}
    field :reason, :string
    field :inserted_at, :utc_datetime, read_after_writes: true
  end
end
