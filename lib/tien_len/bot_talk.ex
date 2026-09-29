defmodule TienLen.BotTalk do
  @moduledoc """
  Bot personalities (decisions BP1–BP4). Pure. A personality changes a bot's name, avatar,
  speed and chat lines, **never** how it chooses cards (that is `TienLen.Bot` and its level).

  `lines(old_room, new_room, events, rng)` returns `[{seat, text}]`: at most one line per bot
  per room change, from **public facts only** (never from the bot's hand). `rng` is
  `%{roll: (-> float), pick: (list -> term)}` (random in the room, fixed in tests).
  """

  alias TienLen.{Commentary, Room}

  @personas [
    %{
      id: :ba_tam,
      name: "Bà Tám",
      avatar: "👵",
      speed: 1.0,
      chance: %{
        start: 0.9,
        play: 0.35,
        chopped: 0.8,
        chops: 0.8,
        other_chop: 0.5,
        win: 0.9,
        lose: 0.9
      },
      lines: %{
        start: [
          "Bài xấu quá trời ơi!",
          "Ai chia bài vậy? Xấu hết biết!",
          "Ván này chắc thua rồi bà con ơi…",
          "Để bà Tám kể nghe, hôm qua ngoài chợ…"
        ],
        play: [
          "Đánh nè, coi chừng nha!",
          "Lá này bà để dành lâu lắm đó!",
          "Trời ơi hồi hộp quá!",
          "Mấy đứa đánh lẹ lên, bà còn đi nấu cơm!"
        ],
        chopped: [
          "Ối trời ơi con heo của tui!",
          "Chặt heo bà già, không biết thương người già hả?"
        ],
        chops: ["Bà chặt nè, ai biểu!", "Xin lỗi nha, bà lỡ tay!"],
        other_chop: ["Trời đất ơi chặt ghê vậy!", "Ác quá à nha!"],
        win: ["Bà nói rồi mà, bài xấu vẫn về nhất!", "Hehe, gừng càng già càng cay!"],
        lose: ["Thua rồi, bà đi kể cả xóm nghe!", "Tại bài xấu chứ bộ!"]
      }
    },
    %{
      id: :ong_cu_non,
      name: "Ông Cụ Non",
      avatar: "👴",
      speed: 2.5,
      chance: %{start: 0.4, play: 0.2, chopped: 0.8, chops: 1.0, win: 0.9, lose: 0.9},
      lines: %{
        start: ["Từ từ, để ông xem bài…", "Hồi xưa ông chơi bài lá, giờ bài này dễ ợt."],
        play: [
          "Từ từ… chậm mà chắc.",
          "Ông đánh lá này, các cháu học hỏi nhé.",
          "Đời người như ván bài, đừng vội."
        ],
        chopped: [
          "Thời trẻ ông cũng bị chặt hoài, quen rồi.",
          "Các cháu bây giờ chặt heo không nương tay."
        ],
        chops: ["Thời trẻ tôi chặt heo cả làng!", "Kinh nghiệm mấy chục năm đó các cháu."],
        win: ["Chậm mà chắc, về nhất rồi nhé!", "Kinh nghiệm cả đấy các cháu."],
        lose: ["Thắng thua là chuyện thường, uống miếng trà đã.", "Ông nhường các cháu thôi."]
      }
    },
    %{
      id: :nong_tinh,
      name: "Thanh Niên Nóng Tính",
      avatar: "😤",
      speed: 0.5,
      chance: %{
        start: 0.5,
        play: 0.2,
        chopped: 1.0,
        chops: 0.8,
        win: 0.9,
        lose: 1.0,
        other_slow: 0.5
      },
      lines: %{
        start: ["Chia lẹ lên!", "Ván này tui ăn hết!"],
        play: ["Đỡ nè!", "Nhanh lên, chờ hoài!", "Có ngon thì chặn đi!"],
        chopped: ["😡 Chơi vậy ai chơi!", "😤 Chặt tui hả? Nhớ mặt đó!", "🤬 Heo của tui mà!"],
        chops: ["Chặt cho chừa!", "Hết đường chạy nha!"],
        win: ["Thấy chưa, nói rồi mà!", "Dễ ợt!"],
        lose: ["😡 Bài gì kỳ vậy! Chơi lại!", "Tại chia bài ép tui!"],
        other_slow: ["Nhanh lên coi, ngủ hả?", "Trời ơi chờ muốn mọc rễ!"]
      }
    }
  ]

  @doc "The personalities, in the order they are given to new bots."
  def personas, do: @personas

  @doc "A personality by id, or `nil`."
  def persona(id), do: Enum.find(@personas, &(&1.id == id))

  @doc "The delay factor of a bot seat (1.0 without a personality)."
  def speed(room, seat) do
    case room.seats[seat] && persona(Map.get(room.seats[seat], :persona)) do
      %{speed: speed} -> speed
      _ -> 1.0
    end
  end

  @doc "The random source used by the room."
  def random, do: %{roll: &:rand.uniform/0, pick: &Enum.random/1}

  @doc "Bot lines of one room change: `[{seat, text}]` (see the moduledoc)."
  def lines(old_room, new_room, events, rng \\ random()) do
    bots =
      for {seat, p} <- new_room.seats,
          persona = persona(Map.get(p, :persona)),
          do: {seat, persona}

    if bots == [] do
      []
    else
      facts = facts(old_room, new_room, events)

      Enum.flat_map(bots, fn {seat, persona} ->
        seat
        |> triggers(facts)
        |> Enum.find_value(fn trigger -> say(persona, trigger, rng) end)
        |> case do
          nil -> []
          text -> [{seat, text}]
        end
      end)
    end
  end

  # public facts of one change
  defp facts(old, new, events) do
    chops =
      for {t, seat, combo} <- events,
          t in [:played, :chopped],
          centre = Commentary.chopped_centre(t, combo, old),
          do: {seat, centre.owner}

    %{
      chops: chops,
      started: Enum.find_value(events, fn e -> match?({:game_started, _}, e) && elem(e, 1) end),
      plays: for({t, seat, _} <- events, t in [:played, :chopped], do: seat),
      first: for({:finished, seat, 1} <- events, do: seat),
      last: last_place(new, events),
      slow: for({:timed_out, seat} <- events, do: seat)
    }
  end

  defp last_place(room, events) do
    if Enum.any?(events, &match?({:game_over, _}, &1)) do
      case Room.last_holder(room.game) do
        nil -> nil
        seat -> seat
      end
    end
  end

  # triggers for one bot seat, most important first
  defp triggers(seat, f) do
    [
      Enum.any?(f.chops, fn {_by, victim} -> victim == seat end) && :chopped,
      Enum.any?(f.chops, fn {by, _victim} -> by == seat end) && :chops,
      seat in f.first && :win,
      f.last == seat && :lose,
      (is_list(f.started) and seat in f.started) && :start,
      f.chops != [] && :other_chop,
      Enum.any?(f.slow, &(&1 != seat)) && :other_slow,
      seat in f.plays && :play
    ]
    |> Enum.filter(& &1)
  end

  defp say(persona, trigger, rng) do
    with lines when is_list(lines) and lines != [] <- persona.lines[trigger],
         chance when is_number(chance) <- persona.chance[trigger],
         true <- rng.roll.() < chance do
      rng.pick.(lines)
    else
      _ -> nil
    end
  end
end
