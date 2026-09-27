defmodule TienLenWeb.CardComponents do
  @moduledoc """
  Card rendering. Card faces are Adrian Kennard's SVG playing cards (CC0 public domain,
  https://www.me.uk/cards/), copied from the original project into
  `priv/static/images/cards/` (`<rank><suit>.svg`, ten is `T`; `1B.svg` is the back).
  """

  use Phoenix.Component

  alias TienLen.Card

  @doc "Static path of a card face."
  def card_src(%Card{rank: rank, suit: suit}) do
    r = if rank == 10, do: "T", else: Card.rank_label(rank)
    s = %{spades: "S", clubs: "C", diamonds: "D", hearts: "H"}[suit]
    "/images/cards/#{r}#{s}.svg"
  end

  attr :card, Card, required: true
  attr :class, :string, default: "w-14 sm:w-16"
  attr :rest, :global

  @doc "A card face (not interactive)."
  def card(assigns) do
    ~H"""
    <img
      src={card_src(@card)}
      alt={Card.display(@card)}
      title={Card.display(@card)}
      class={["select-none rounded-md shadow", @class]}
      draggable="false"
      {@rest}
    />
    """
  end

  attr :count, :integer, required: true

  @doc "A small pile of card backs with a count."
  def card_backs(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <img src="/images/cards/1B.svg" alt="" class="w-6 rounded-sm shadow" draggable="false" />
      <span class="text-sm font-semibold tabular-nums">{@count}</span>
    </div>
    """
  end
end
