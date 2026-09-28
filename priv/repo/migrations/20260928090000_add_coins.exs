defmodule TienLen.Repo.Migrations.AddCoins do
  use Ecto.Migration

  # Coins (C1–C10, E1–E9). Existing accounts receive the 1,000 starting coins (E9).
  def up do
    alter table(:users) do
      add :coins, :bigint, null: false, default: 0
      # last Vietnam calendar day the daily bonus / relief was claimed (E8)
      add :daily_bonus_on, :date
      add :relief_on, :date
    end

    create constraint(:users, :coins_not_negative, check: "coins >= 0")

    create table(:coin_transactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :amount, :bigint, null: false
      add :balance_after, :bigint, null: false
      add :reason, :string, null: false
      add :counterparty_id, references(:users, on_delete: :nilify_all)
      add :ref, :string
      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create index(:coin_transactions, [:user_id, :inserted_at])

    # one row per applied settlement / claim: makes every coin operation idempotent
    create table(:coin_settlements, primary_key: false) do
      add :key, :string, primary_key: true
      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    execute "UPDATE users SET coins = 1000"

    execute """
    INSERT INTO coin_transactions (user_id, amount, balance_after, reason, ref)
    SELECT id, 1000, 1000, 'starting_grant', 'E9' FROM users
    """
  end

  def down do
    drop table(:coin_settlements)
    drop table(:coin_transactions)
    drop constraint(:users, :coins_not_negative)

    alter table(:users) do
      remove :coins
      remove :daily_bonus_on
      remove :relief_on
    end
  end
end
