defmodule TienLen.Repo.Migrations.AddChatInvites do
  use Ecto.Migration

  # G9 "Không nhận lời mời" and G12 chat mute; chat messages themselves are never stored (CH2).
  def change do
    alter table(:users) do
      add :accept_invites, :boolean, null: false, default: true
      add :muted_until, :utc_datetime
    end
  end
end
