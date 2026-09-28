defmodule TienLen.Stats.GamePlayer do
  @moduledoc "One player's result in a finished game (Phase 13)."
  use Ecto.Schema

  schema "game_players" do
    belongs_to :game, TienLen.Stats.GameRecord
    belongs_to :user, TienLen.Accounts.User
    field :seat, :integer
    field :place, :integer
    field :won, :boolean
    field :removed, :boolean, default: false
  end
end
