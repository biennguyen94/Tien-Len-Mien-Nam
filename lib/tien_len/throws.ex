defmodule TienLen.Throws do
  @moduledoc """
  Items a seated player can throw at another seat (decisions TH1–TH4, RULES T26). Pure
  catalogue; `TienLen.RoomServer.throw/4` validates, spends the price through
  `TienLen.Economy.spend/5` and broadcasts `{:thrown, room_id, from_seat, to_seat, item_id}`.
  A throw never touches the game.
  """

  # mark: what stays on the target seat for 3 s
  @items [
    %{id: "tomato", emoji: "🍅", name: "Cà chua", price: 1, mark: "💦"},
    %{id: "egg", emoji: "🥚", name: "Trứng thối", price: 2, mark: "🍳"},
    %{id: "slipper", emoji: "🩴", name: "Dép", price: 3, mark: "💫"},
    %{id: "rose", emoji: "🌹", name: "Hoa hồng", price: 5, mark: "💕"}
  ]

  @cooldown 3_000

  @doc "The items, cheapest first."
  def items, do: @items

  @doc "An item by id, or `nil`."
  def item(id), do: Enum.find(@items, &(&1.id == id))

  @doc "Minimum time between two throws of one player (ms, TH3)."
  def cooldown, do: @cooldown
end
