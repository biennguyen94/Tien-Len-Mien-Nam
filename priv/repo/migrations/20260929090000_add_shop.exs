defmodule TienLen.Repo.Migrations.AddShop do
  use Ecto.Migration

  # Batch 14 (SH1–SH3): bought card backs / table themes and the equipped ones
  def change do
    alter table(:users) do
      add :card_back, :string
      add :table_theme, :string
    end

    create table(:user_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, :string, null: false
      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:user_items, [:user_id, :item_id])
  end
end
