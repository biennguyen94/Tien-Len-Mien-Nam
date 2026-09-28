defmodule TienLen.Replay do
  @moduledoc """
  Rebuilds a recorded game step by step from its replay (V5): the dealt hands and the public
  events stored at game over. Pure. After the game every hand is shown (owner's decision V6).

  `frames/1` returns one frame per event, frame 0 being the deal. A frame has `hands`
  (seat => cards left), `centre` (`nil` or `%{seat, cards, type, chop}`), `passed`,
  `finished` (in order), `removed` and the `event` that led to it (a map with atom keys).
  """

  alias TienLen.Card

  @doc "Seat names: `%{seat => name}`."
  def names(%{"seats" => seats}), do: Map.new(seats, &{&1["seat"], &1["name"]})

  @doc "All frames of a replay."
  def frames(%{"hands" => hands, "events" => events}) do
    start = %{
      hands: Map.new(hands, fn {seat, codes} -> {String.to_integer(seat), parse(codes)} end),
      centre: nil,
      passed: [],
      finished: [],
      removed: [],
      event: %{type: :deal}
    }

    {frames, _} =
      Enum.map_reduce(events, start, fn e, acc ->
        next = step(acc, decode(e))
        {next, next}
      end)

    [start | frames]
  end

  defp step(f, %{type: t, seat: s, cards: cards} = e) when t in [:played, :chopped] do
    %{
      f
      | hands: Map.update(f.hands, s, [], &(&1 -- cards)),
        centre: %{seat: s, cards: cards, type: e.combo, chop: t == :chopped},
        event: e
    }
  end

  defp step(f, %{type: :passed, seat: s} = e), do: %{f | passed: f.passed ++ [s], event: e}
  defp step(f, %{type: :round_ended} = e), do: %{f | centre: nil, passed: [], event: e}
  defp step(f, %{type: :finished, seat: s} = e), do: %{f | finished: f.finished ++ [s], event: e}
  defp step(f, %{type: :removed, seat: s} = e), do: %{f | removed: f.removed ++ [s], event: e}
  defp step(f, e), do: %{f | event: e}

  defp decode(%{"t" => t} = e) do
    %{
      type: String.to_existing_atom(t),
      seat: e["s"],
      cards: if(e["c"], do: parse(e["c"])),
      combo: if(e["k"], do: String.to_existing_atom(e["k"])),
      place: e["p"],
      ranking: e["r"],
      winners: Enum.map(e["w"] || [], fn [s, type] -> {s, String.to_existing_atom(type)} end),
      transfers: e["x"] || []
    }
  end

  defp parse(codes), do: Enum.map(codes, &Card.parse!/1)
end
