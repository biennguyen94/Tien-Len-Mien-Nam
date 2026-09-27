defmodule TienLen.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      # stored lowercase; unique (case-insensitive by construction)
      add :username, :string, null: false, size: 20
      add :display_name, :string, null: false, size: 80
      add :hashed_password, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
  end
end
