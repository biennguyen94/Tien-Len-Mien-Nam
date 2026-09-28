defmodule TienLen.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :room_id, :string, null: false
      add :player_count, :integer, null: false
      add :instant_win, :boolean, null: false, default: false
      add :finished_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:games, [:finished_at])

    create table(:game_players) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :seat, :integer, null: false
      # 1 = Nhất; instant-win games: all instant winners 1, everyone else 2 (tied)
      add :place, :integer, null: false
      add :won, :boolean, null: false
      add :removed, :boolean, null: false, default: false
    end

    create unique_index(:game_players, [:game_id, :user_id])
    create index(:game_players, [:user_id])
  end
end
