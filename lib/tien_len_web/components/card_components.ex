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
  attr :back, :string, default: nil, doc: "the seat's card back (SH1), nil = classic"

  @doc "A small pile of card backs with a count."
  def card_backs(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <.card_back back={@back} class="w-6 rounded-sm shadow text-[0.65rem]" />
      <span class="text-sm font-semibold tabular-nums">{@count}</span>
    </div>
    """
  end

  attr :back, :string, default: nil
  attr :class, :string, default: "w-6 rounded-sm shadow"
  attr :rest, :global

  @doc "One card back: the classic SVG, or a shop design (CSS `back-<id>`, SH1)."
  def card_back(assigns) do
    assigns =
      assign(assigns, :item, TienLen.Shop.item(TienLen.Shop.valid(assigns.back, :card_back)))

    ~H"""
    <img
      :if={@item.price == 0}
      src="/images/cards/1B.svg"
      alt=""
      class={@class}
      draggable="false"
      {@rest}
    />
    <div
      :if={@item.price > 0}
      class={["card-back-custom", "back-" <> @item.id, @class]}
      title={@item.name}
      {@rest}
    >
      {@item.icon}
    </div>
    """
  end
end
