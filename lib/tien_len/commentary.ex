defmodule TienLen.Commentary do
  @moduledoc """
  The table's commentator (decisions BL1–BL3, RC1). Pure: turns the public events of one room
  change into funny Vietnamese lines. `TienLen.RoomServer` posts them in the room chat as
  "🎙️ Bình luận viên".

  `lines(old_room, new_room, events, pick)`: `old_room` is the room before the change (it still
  has the chopped centre and the name of a player who just left), `pick` chooses one template
  of a list (`&Enum.random/1` in the room, a fixed choice in tests).

  Only public facts are used, plus, at game over, how many 2s the thối heo loser still held
  (BL2).
  """

  alias TienLen.{Combination, Game, Room, Rules}

  @name "🎙️ Bình luận viên"

  @templates %{
    chop: [
      "💥 Ối dồi ôi! {a} vừa chặt heo của {b}, heo khóc thét éc éc!",
      "🔪 {a} rút dao chặt phăng con heo của {b}!",
      "🐷💨 Heo của {b} bị {a} xẻ thịt ngay tại trận!",
      "😱 {b} ơi, heo đâu rồi? {a} làm thịt mất rồi!"
    ],
    chop_again: [
      "💣 Chặt chồng! {a} chặt luôn cả {b}, ai chặt người đó chịu!",
      "🔥 {a} chặt chồng lên {b}, sòng bài nóng rực!",
      "⚔️ Tưởng yên, ai dè {a} chặt ngược {b}!"
    ],
    last_card: [
      "📢 {a} BÁO 1! Mọi người cẩn thận!",
      "🚨 {a} còn đúng 1 lá, chặn ngay kẻo muộn!",
      "☝️ {a} chỉ còn 1 lá, cả làng nín thở!"
    ],
    first: [
      "🥇 {a} về nhất, nhẹ nhàng như đi chợ!",
      "🏆 {a} sạch bài! Về nhất rồi nha!",
      "👑 {a} về nhất, xin mời các vị còn lại tiếp tục đau khổ."
    ],
    timeout: [
      "😴 {a} ngủ gật, hết giờ rồi!",
      "⏰ {a} ơi dậy đi, hết 20 giây rồi!",
      "🐢 {a} suy nghĩ lâu quá, máy đánh giùm luôn!"
    ],
    instant: [
      "🎆 {a} TỚI TRẮNG! Cả làng nín thở!",
      "🎇 Trời ơi {a} tới trắng! Chưa đánh đã thắng!",
      "🧧 {a} tới trắng, lộc về như nước!"
    ],
    thoi: [
      "🐷 {a} ôm {n} con heo về chuồng, mất trắng!",
      "🐖 {a} thối {n} heo! Nuôi heo chi mà kỹ vậy?",
      "🥲 {a} để dành {n} con heo tới cuối, heo buồn lắm!"
    ],
    cong: [
      "🥶 {a} bị cóng, chưa kịp đánh lá nào…",
      "🧊 {a} cóng nguyên 13 lá, lạnh như tủ đá!",
      "🙈 {a} ôm trọn 13 lá, cóng rồi!"
    ],
    runaway: [
      "🏃💨 {a} đã chạy mất dép 🩴, bị loại khỏi ván!",
      "🩴 {a} bỏ chạy giữa ván, để lại một chiếc dép!",
      "🏃 {a} xin phép đi chợ… luôn, bị loại khỏi ván!"
    ],
    lost_signal: [
      "📵 {a} mất sóng lâu quá, bị loại khỏi ván!",
      "📡 Alo alo, {a} ơi? Mất sóng rồi, bị loại khỏi ván!"
    ]
  }

  @doc "Name shown for the commentator's chat lines."
  def name, do: @name

  @doc "All templates by kind (for tests and docs)."
  def templates, do: @templates

  @doc "The lines for one room change (see the moduledoc)."
  @spec lines(Room.t(), Room.t(), list(), ([String.t()] -> String.t())) :: [String.t()]
  def lines(old_room, new_room, events, pick \\ &Enum.random/1) do
    name = fn seat -> seat_name(old_room, new_room, seat) end
    say = fn kind, vars -> fill(pick.(@templates[kind]), vars) end

    Enum.flat_map(events, fn event ->
      event_lines(event, old_room, new_room, events, name, say)
    end)
  end

  defp event_lines({type, seat, combo}, old, new, _events, name, say)
       when type in [:played, :chopped] do
    chop = chop_line(type, seat, combo, old, name, say)
    last = if cards_left(new, seat) == 1, do: [say.(:last_card, a: name.(seat))], else: []
    chop ++ last
  end

  defp event_lines({:finished, seat, 1}, _old, _new, _events, name, say),
    do: [say.(:first, a: name.(seat))]

  defp event_lines({:timed_out, seat}, _old, new, _events, name, say) do
    if new.seats[seat] && new.seats[seat].connected,
      do: [say.(:timeout, a: name.(seat))],
      else: []
  end

  defp event_lines({:instant_win, winners}, _old, _new, _events, name, say),
    do: Enum.map(winners, fn {seat, _type} -> say.(:instant, a: name.(seat)) end)

  defp event_lines({:game_over, _ranking}, _old, new, _events, name, say),
    do: loser_lines(new.game, name, say)

  defp event_lines({:removed, seat}, _old, _new, events, name, say) do
    cond do
      {:kicked, seat} in events -> []
      {:left, seat} in events -> [say.(:runaway, a: name.(seat))]
      true -> [say.(:lost_signal, a: name.(seat))]
    end
  end

  defp event_lines(_event, _old, _new, _events, _name, _say), do: []

  # A chop: an out-of-turn four-pair, or a bomb played on a chop target (like the P2 count).
  defp chop_line(type, seat, combo, old, name, say) do
    case chopped_centre(type, combo, old) do
      nil ->
        []

      centre ->
        kind = if Game.twos_units(centre.combo.cards) > 0, do: :chop, else: :chop_again
        [say.(kind, a: name.(seat), b: name.(centre.owner))]
    end
  end

  @doc """
  The centre that a `{:played | :chopped, seat, combo}` event chopped (its `owner` is the
  victim), or `nil`. `old` is the room before the change.
  """
  def chopped_centre(type, combo, old) do
    centre = old.game && old.game.centre

    if centre != nil and (type == :chopped or Combination.bomb?(combo)) and
         Rules.chop_target?(centre),
       do: centre
  end

  # At a normal game over the last player still holding cards may be cóng and / or thối heo.
  defp loser_lines(%Game{} = game, name, say) do
    case Room.last_holder(game) do
      nil ->
        []

      seat ->
        hand = game.hands[seat]
        twos = Enum.count(hand, &(&1.rank == 15))
        cong = if length(hand) == 13, do: [say.(:cong, a: name.(seat))], else: []
        thoi = if twos > 0, do: [say.(:thoi, a: name.(seat), n: twos)], else: []
        cong ++ thoi
    end
  end

  defp loser_lines(_game, _name, _say), do: []

  defp cards_left(%Room{status: :playing, game: %Game{} = game}, seat),
    do: length(Map.get(game.hands, seat, []))

  defp cards_left(_room, _seat), do: nil

  defp seat_name(old, new, seat) do
    case new.seats[seat] || old.seats[seat] do
      %{name: name} -> name
      _ -> "?"
    end
  end

  @doc """
  Sound / visual effect kinds of one room change (SF1), from public events only:
  `"pig"` (a play with a 2), `"chop"` (a chặt heo / chặt chồng), `"confetti"` (tới trắng).
  """
  @spec effects(Room.t(), list()) :: [String.t()]
  def effects(old_room, events) do
    events
    |> Enum.flat_map(fn
      {type, _seat, combo} when type in [:played, :chopped] ->
        chop = if chopped_centre(type, combo, old_room), do: ["chop"], else: []
        pig = if Enum.any?(combo.cards, &(&1.rank == 15)), do: ["pig"], else: []
        chop ++ pig

      {:instant_win, _} ->
        ["confetti"]

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp fill(template, vars) do
    Enum.reduce(vars, template, fn {key, value}, acc ->
      String.replace(acc, "{#{key}}", to_string(value))
    end)
  end
end
