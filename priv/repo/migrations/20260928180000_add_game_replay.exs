defmodule TienLen.Repo.Migrations.AddGameReplay do
  use Ecto.Migration

  # V5: the dealt hands and the public events of a recorded game, stored at game over
  def change do
    alter table(:games) do
      add :replay, :map
    end
  end
end
