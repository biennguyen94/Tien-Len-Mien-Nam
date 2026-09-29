defmodule TienLen.Events do
  @moduledoc """
  Seasonal events (decisions EV1–EV3), started and stopped by an admin
  (`TienLen.Admin.set_event/2`, stored as the setting `season_event`).

  - **Tết** (EV2): every 1st place of a recorded game gets a random lì xì through
    `TienLen.Economy.grant/5` (key `lixi:<game ref>:<user>`, reason `lixi`), at most
    #{10} per player per Vietnam day.
  - **Trung thu** (EV3): avatars wear a 🏮 (`TienLenWeb.Text.avatar/1`).
  """

  import Ecto.Query

  alias TienLen.{Economy, Repo, Settings}
  alias TienLen.Economy.CoinTransaction

  @kinds ~w(tet trung_thu)
  @daily_cap 10
  # amount => weight (out of 100): small amounts are more likely
  @lixi [{8, 30}, {18, 25}, {28, 15}, {38, 10}, {58, 8}, {68, 6}, {88, 4}, {168, 2}]

  @doc "Event ids an admin can start."
  def kinds, do: @kinds

  @doc "The running event, or nil."
  def current, do: Settings.event()

  @doc "Name and banner text of an event."
  def label("tet"), do: {"Tết", "🧧 Sự kiện Tết: mỗi ván về nhất được lì xì ngẫu nhiên!"}
  def label("trung_thu"), do: {"Trung thu", "🏮 Sự kiện Trung thu: ai cũng được đội đèn lồng!"}
  def label(_), do: nil

  @doc "The possible lì xì amounts with their weights."
  def lixi_table, do: @lixi

  @doc "Maximum lì xì per player per Vietnam day."
  def daily_cap, do: @daily_cap

  @doc "The lì xì amount for a roll in `0..99`."
  def draw(roll) when roll in 0..99 do
    Enum.reduce_while(@lixi, roll, fn {amount, weight}, left ->
      if left < weight, do: {:halt, amount}, else: {:cont, left - weight}
    end)
  end

  @doc """
  Gives `user_id` a lì xì for the game `game_ref` (a 1st place, EV2).
  `{:ok, amount}` or `{:error, :daily_cap | :already_claimed | :not_found}`.
  """
  def lixi(user_id, game_ref, roll \\ :rand.uniform(100) - 1) do
    {from, to} = Economy.vn_day_bounds(Economy.vn_today())

    today =
      Repo.aggregate(
        from(t in CoinTransaction,
          where:
            t.user_id == ^user_id and t.reason == "lixi" and t.inserted_at >= ^from and
              t.inserted_at < ^to
        ),
        :count
      )

    if today >= @daily_cap do
      {:error, :daily_cap}
    else
      amount = draw(roll)

      with {:ok, _balance} <-
             Economy.grant(user_id, "lixi:#{game_ref}:#{user_id}", amount, "lixi", "Lì xì Tết"),
           do: {:ok, amount}
    end
  end
end
