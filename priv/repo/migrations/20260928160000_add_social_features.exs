defmodule TienLen.Repo.Migrations.AddSocialFeatures do
  use Ecto.Migration

  # Batch 11: profiles (P1–P4), friends (FR1–FR5); missions and seasons use the ledger and
  # coin_settlements keys, so they need no table of their own.
  def change do
    alter table(:users) do
      add :avatar, :string
    end

    # per-player facts of a recorded game (P2): chặt heo count, net coins, tới trắng
    alter table(:game_players) do
      add :chops, :integer, null: false, default: 0
      add :coins, :bigint, null: false, default: 0
      add :instant, :boolean, null: false, default: false
    end

    create table(:friendships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :friend_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      timestamps type: :utc_datetime
    end

    create unique_index(:friendships, [:user_id, :friend_id])
    create index(:friendships, [:friend_id])

    create constraint(:friendships, :not_self, check: "user_id <> friend_id")

    create constraint(:friendships, :valid_status, check: "status IN ('pending', 'accepted')")
  end
end
