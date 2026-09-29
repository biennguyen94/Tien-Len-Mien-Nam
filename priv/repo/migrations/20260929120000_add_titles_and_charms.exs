defmodule TienLen.Repo.Migrations.AddTitlesAndCharms do
  use Ecto.Migration

  # Batch 15: per-player facts for the shame titles (XH2) and the worn charm (TB2)
  def change do
    alter table(:game_players) do
      add :thoi, :integer, null: false, default: 0
      add :cong, :boolean, null: false, default: false
      add :passes, :integer, null: false, default: 0
      add :plays, :integer, null: false, default: 0
      add :timeouts, :integer, null: false, default: 0
    end

    alter table(:users) do
      add :charm, :string
    end
  end
end
