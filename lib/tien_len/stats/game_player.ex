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
    # P2
    field :chops, :integer, default: 0
    field :coins, :integer, default: 0
    field :instant, :boolean, default: false
    # XH2
    field :thoi, :integer, default: 0
    field :cong, :boolean, default: false
    field :passes, :integer, default: 0
    field :plays, :integer, default: 0
    field :timeouts, :integer, default: 0
  end
end
