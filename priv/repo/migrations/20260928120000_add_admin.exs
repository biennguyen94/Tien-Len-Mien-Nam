defmodule TienLen.Repo.Migrations.AddAdmin do
  use Ecto.Migration

  # Admin (AD1–AD9, F1–F8).
  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "player"
      add :locked_at, :utc_datetime
    end

    create constraint(:users, :valid_role, check: "role IN ('player', 'admin')")

    # AD2: append-only audit log of admin actions
    create table(:admin_actions) do
      # nil = done by the server command (first admin)
      add :admin_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :target_user_id, references(:users, on_delete: :nilify_all)
      add :details, :map, null: false, default: %{}
      add :reason, :text
      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create index(:admin_actions, [:inserted_at])

    # AD9 / F7: economy settings and the lobby announcement
    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text, null: false
      add :updated_at, :utc_datetime, null: false, default: fragment("now()")
    end

    # AD8: link a recorded game to its coin settlements (ledger refs start with it)
    alter table(:games) do
      add :ref, :string
    end
  end
end
