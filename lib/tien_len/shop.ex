defmodule TienLen.Shop do
  @moduledoc """
  The shop (decisions SH1–SH3, RULES T26): card backs and table themes bought with coins.

  - The catalogue and prices are fixed here; how an item looks is CSS only
    (`assets/css/app.css`, classes `back-<id>` and `felt-<id>`).
  - Each kind has one free default (`"classic"`), owned by everyone.
  - `buy/2` spends the price and adds the item in **one transaction**
    (`TienLen.Economy.spend/5`); the unique `(user_id, item_id)` index means an item is never
    paid twice. No refunds, gifts or selling.
  - `equip/2` is free and only for owned items. The card back is shown to everyone at the
    table (it is taken into the room on join), the table theme only to its owner.
  """

  import Ecto.Query

  alias TienLen.{Economy, Repo}
  alias TienLen.Accounts.User

  @items [
    # card backs (ids are unique across both kinds)
    %{id: "classic", kind: :card_back, name: "Cổ điển", icon: "🂠", price: 0},
    %{id: "heo_dat", kind: :card_back, name: "Heo đất", icon: "🐷", price: 400},
    %{id: "meo_u", kind: :card_back, name: "Mèo ú", icon: "🐱", price: 400},
    %{id: "lixi", kind: :card_back, name: "Bao lì xì", icon: "🧧", price: 500},
    %{id: "tra_sua", kind: :card_back, name: "Trà sữa trân châu", icon: "🧋", price: 500},
    %{id: "banh_mi", kind: :card_back, name: "Bánh mì Sài Gòn", icon: "🥖", price: 500},
    %{id: "hoa_mai", kind: :card_back, name: "Hoa mai", icon: "🌼", price: 600},
    %{id: "ngan_ha", kind: :card_back, name: "Dải ngân hà", icon: "✨", price: 1_000},
    %{id: "rong_vang", kind: :card_back, name: "Rồng vàng", icon: "🐉", price: 1_500},
    # table themes
    %{id: "felt", kind: :table, name: "Nỉ xanh cổ điển", icon: "🟩", price: 0},
    %{id: "quan_coc", kind: :table, name: "Quán cóc vỉa hè", icon: "🪑", price: 500},
    %{id: "ca_phe", kind: :table, name: "Cà phê sữa đá", icon: "☕", price: 500},
    %{id: "ruong_lua", kind: :table, name: "Ruộng lúa quê nhà", icon: "🌾", price: 600},
    %{id: "bai_bien", kind: :table, name: "Bãi biển Vũng Tàu", icon: "🏖️", price: 700},
    %{id: "tet", kind: :table, name: "Tết đỏ vàng", icon: "🧧", price: 800},
    %{id: "trung_thu", kind: :table, name: "Đêm Trung thu", icon: "🏮", price: 800},
    %{id: "vu_tru", kind: :table, name: "Vũ trụ bao la", icon: "🌌", price: 1_200},
    %{id: "song_bai", kind: :table, name: "Sòng bài Las Vegas", icon: "🎰", price: 1_500}
  ]

  @defaults %{card_back: "classic", table: "felt"}

  @doc "Every item, by kind, cheapest first."
  def items, do: @items

  @doc "Items of one kind (`:card_back` or `:table`)."
  def items(kind), do: Enum.filter(@items, &(&1.kind == kind))

  @doc "An item by id, or `nil`."
  def item(id), do: Enum.find(@items, &(&1.id == id))

  @doc "The free default id of a kind."
  def default(kind), do: Map.fetch!(@defaults, kind)

  @doc "The user's equipped item id of a kind (the default when none or unknown)."
  def equipped(%User{} = user, :card_back), do: valid(user.card_back, :card_back)
  def equipped(%User{} = user, :table), do: valid(user.table_theme, :table)
  def equipped(_user, kind), do: default(kind)

  @doc "A card back id as shown at the table (unknown or nil → the default)."
  def valid(id, kind) do
    case item(id) do
      %{kind: ^kind} -> id
      _ -> default(kind)
    end
  end

  @doc "Ids the user owns (free items included)."
  def owned(user_id) when is_integer(user_id) do
    bought = Repo.all(from i in "user_items", where: i.user_id == ^user_id, select: i.item_id)
    MapSet.new(bought ++ for(i <- @items, i.price == 0, do: i.id))
  end

  def owned(_), do: MapSet.new(for i <- @items, i.price == 0, do: i.id)

  @doc """
  Buys an item: `{:ok, balance}` or `{:error, :not_found | :already_owned | :cannot_afford}`.
  """
  def buy(user_id, item_id) do
    case item(item_id) do
      nil ->
        {:error, :not_found}

      %{price: 0} ->
        {:error, :already_owned}

      item ->
        if MapSet.member?(owned(user_id), item.id),
          do: {:error, :already_owned},
          else: pay(user_id, item)
    end
  end

  # the unique index still guards a race between two purchases of the same item
  defp pay(user_id, item) do
    case Economy.spend(user_id, item.price, "shop", item.name, fn -> add(user_id, item.id) end) do
      {:error, :insufficient_coins} -> {:error, :cannot_afford}
      other -> other
    end
  end

  defp add(user_id, item_id) do
    case Repo.insert_all("user_items", [%{user_id: user_id, item_id: item_id}],
           on_conflict: :nothing
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :already_owned}
    end
  end

  @doc "Equips an owned item: `{:ok, user}` or `{:error, :not_found | :not_owned}`."
  def equip(%User{} = user, item_id) do
    case item(item_id) do
      nil ->
        {:error, :not_found}

      item ->
        if MapSet.member?(owned(user.id), item.id) do
          field = if item.kind == :card_back, do: :card_back, else: :table_theme
          user |> Ecto.Changeset.change([{field, item.id}]) |> Repo.update()
        else
          {:error, :not_owned}
        end
    end
  end
end
