defmodule TienLen.Stats.GameRecord do
  @moduledoc "A finished game (Phase 13)."
  use Ecto.Schema

  schema "games" do
    field :room_id, :string
    field :player_count, :integer
    field :instant_win, :boolean, default: false
    field :finished_at, :utc_datetime
    has_many :players, TienLen.Stats.GamePlayer, foreign_key: :game_id

    timestamps type: :utc_datetime, updated_at: false
  end
end
