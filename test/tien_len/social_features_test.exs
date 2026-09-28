defmodule TienLen.SocialFeaturesTest do
  @moduledoc "Batch 11: per-player game facts, profiles, avatars, friends, missions, seasons."
  use TienLenWeb.ConnCase, async: true

  import Ecto.Query

  alias TienLen.{Accounts, Card, Economy, Friends, Missions, Repo, Room, Seasons, Stats}
  alias TienLen.Stats.GameRecord

  defp user(name) do
    _ = login_conn(name)
    test_user(name)
  end

  # a recorded 2-player game; `facts` per user: place 1 or 2, chops, coins, instant
  defp record!(players, finished_at \\ nil) do
    {:ok, game} =
      Stats.record(%{
        room_id: "t",
        ref: "room:t:game:#{System.unique_integer([:positive])}",
        player_count: length(players),
        instant_win: Enum.any?(players, &Map.get(&1, :instant, false)),
        players:
          Enum.with_index(players, fn p, seat ->
            Map.merge(%{seat: seat, won: p.place == 1, removed: false}, p)
          end)
      })

    if finished_at do
      Repo.update_all(from(g in GameRecord, where: g.id == ^game.id),
        set: [finished_at: finished_at]
      )
    end

    game
  end

  describe "chops and facts per player (P2)" do
    test "a three-pair on a 2 counts as a chop and reaches the result" do
      hands = %{0 => Card.parse_many!("3S 2H 9C"), 1 => Card.parse_many!("4S 4C 5S 5C 6S 6C 9D")}
      room = Room.new("r")
      {:ok, room, _, _} = Room.join(room, :a, "A")
      {:ok, room, _, _} = Room.join(room, :b, "B")
      {:ok, room, _} = Room.start_game(room, :a, {:hands, hands})
      {:ok, room, _} = Room.command(room, :a, {:play, Card.parse_many!("3S")})
      {:ok, room, _} = Room.command(room, :b, :pass)
      {:ok, room, _} = Room.command(room, :a, {:play, Card.parse_many!("2H")})
      {:ok, room, _} = Room.command(room, :b, {:play, Card.parse_many!("4S 4C 5S 5C 6S 6C")})
      assert room.game_chops == %{1 => 1}
      {:ok, room, _} = Room.command(room, :a, :pass)
      {:ok, room, _} = Room.command(room, :b, {:play, Card.parse_many!("9D")})

      assert %{players: players} = Room.result(room)
      assert %{seat: 1, chops: 1, won: true, instant: false} = Enum.find(players, &(&1.seat == 1))
      assert %{seat: 0, chops: 0} = Enum.find(players, &(&1.seat == 0))
    end

    test "profile numbers and daily counts come from the recorded facts" do
      a = user("An")
      b = user("Binh")

      record!([
        %{user_id: a.id, place: 1, chops: 2, coins: 300},
        %{user_id: b.id, place: 2, coins: -300}
      ])

      record!([
        %{user_id: a.id, place: 2, coins: -50},
        %{user_id: b.id, place: 1, coins: 50, instant: true}
      ])

      assert %{
               games: 2,
               wins: 1,
               win_rate: 0.5,
               avg_place: 1.5,
               chops: 2,
               instant_wins: 0,
               coins: 250,
               best_coins: 300
             } = Stats.profile(a.id)

      assert %{instant_wins: 1, chops: 0} = Stats.profile(b.id)
      assert %{games: 0, wins: 0, win_rate: +0.0, best_coins: 0} = Stats.profile(user("Cuong").id)
      today = Economy.vn_day_bounds(Economy.vn_today())
      assert Stats.counts(a.id, today) == %{games: 2, wins: 1, chops: 2}
    end
  end

  describe "avatars (P3)" do
    test "only the offered avatars" do
      u = user("An")
      assert {:ok, %{avatar: "🐯"}} = Accounts.set_avatar(u, "🐯")
      assert Accounts.set_avatar(u, "<script>") == {:error, :invalid_avatar}
      assert Accounts.get_by_username(String.upcase(u.username)).avatar == "🐯"
    end
  end

  describe "friends (FR1–FR5)" do
    test "request, accept, remove; notifications to both" do
      a = user("An")
      b = user("Binh")
      Phoenix.PubSub.subscribe(TienLen.PubSub, TienLen.Admin.user_topic(b.id))

      assert {:ok, :requested} = Friends.request(a.id, b.id)
      assert_receive {:friends_changed}
      assert Friends.relation(a.id, b.id) == :outgoing
      assert Friends.relation(b.id, a.id) == :incoming
      assert Friends.incoming_count(b.id) == 1
      assert Friends.request(a.id, b.id) == {:error, :request_pending}

      assert {:ok, :accepted} = Friends.accept(b.id, a.id)
      assert Friends.relation(a.id, b.id) == :friends
      assert [%{id: bid}] = Friends.friends(a.id)
      assert bid == b.id
      assert Friends.request(b.id, a.id) == {:error, :already_friends}

      assert :ok = Friends.remove(b.id, a.id)
      assert Friends.relation(a.id, b.id) == :none
      assert Friends.remove(b.id, a.id) == {:error, :not_found}
    end

    test "asking someone who asked you accepts; decline and cancel; refusals" do
      a = user("An")
      b = user("Binh")
      c = user("Cuong")
      {:ok, :requested} = Friends.request(a.id, b.id)
      assert {:ok, :accepted} = Friends.request(b.id, a.id)

      {:ok, :requested} = Friends.request(c.id, a.id)
      assert :ok = Friends.decline(a.id, c.id)
      assert Friends.relation(a.id, c.id) == :none
      {:ok, :requested} = Friends.request(a.id, c.id)
      assert :ok = Friends.cancel(a.id, c.id)
      assert Friends.outgoing(a.id) == []

      assert Friends.request(a.id, a.id) == {:error, :cannot_friend_self}
      assert Friends.request(a.id, -1) == {:error, :not_found}
      assert Friends.accept(a.id, c.id) == {:error, :not_found}
    end

    test "at most 10 requests a minute" do
      a = user("Spammer")
      targets = for i <- 1..11, do: user("T#{i}")
      results = Enum.map(targets, &Friends.request(a.id, &1.id))
      assert Enum.take(results, 10) |> Enum.all?(&(&1 == {:ok, :requested}))
      assert List.last(results) == {:error, :friend_too_fast}
    end
  end

  describe "missions (M1–M4)" do
    test "progress from today's games; claim once when done" do
      a = user("An")
      b = user("Binh")
      assert [%{key: "play", progress: 0, goal: 5, reward: 100} | _] = Missions.today(a.id)
      assert Missions.claim(a.id, "play") == {:error, :mission_not_done}
      assert Missions.claim(a.id, "nope") == {:error, :unknown_mission}

      for _ <- 1..5,
          do: record!([%{user_id: a.id, place: 1, chops: 1}, %{user_id: b.id, place: 2}])

      # yesterday's game does not count
      record!(
        [%{user_id: b.id, place: 1}, %{user_id: a.id, place: 2}],
        DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second)
      )

      missions = Map.new(Missions.today(a.id), &{&1.key, &1})
      assert %{progress: 5, done: true, claimed: false} = missions["play"]
      assert %{progress: 2, done: true} = missions["win"]
      assert %{progress: 1, done: true} = missions["chop"]
      assert missions_b = Map.new(Missions.today(b.id), &{&1.key, &1})
      assert %{progress: 0, done: false} = missions_b["win"]

      before = Economy.balance(a.id)
      assert {:ok, balance} = Missions.claim(a.id, "play")
      assert balance == before + 100
      assert Missions.claim(a.id, "play") == {:error, :already_claimed}
      assert %{claimed: true} = Enum.find(Missions.today(a.id), &(&1.key == "play"))
      assert [%{reason: "mission", amount: 100, ref: "Chơi 5 ván"} | _] = Economy.history(a.id)
    end
  end

  describe "seasons (S1–S4)" do
    test "weekly standings, payout to the top 3 with a win, once" do
      [a, b, c, d] = for n <- ~w(An Binh Cuong Dung), do: user(n)
      monday = Seasons.week_start()
      last = Date.add(monday, -7)
      {from, _} = Seasons.period(last)
      in_last = DateTime.add(from, 3600, :second)

      # last week: a 2 wins, b 1 win, c 0 wins; d plays this week only
      record!([%{user_id: a.id, place: 1}, %{user_id: c.id, place: 2}], in_last)
      record!([%{user_id: a.id, place: 1}, %{user_id: b.id, place: 2}], in_last)
      record!([%{user_id: b.id, place: 1}, %{user_id: c.id, place: 2}], in_last)
      record!([%{user_id: d.id, place: 1}, %{user_id: c.id, place: 2}])

      assert [%{user_id: first, wins: 2}, %{user_id: second, wins: 1}, %{user_id: third, wins: 0}] =
               Seasons.standings(last)

      assert {first, second, third} == {a.id, b.id, c.id}
      assert [%{user_id: did}, _] = Seasons.standings(monday)
      assert did == d.id

      assert Seasons.payout(monday) == {:error, :season_not_over}
      balances = Economy.balances([a.id, b.id, c.id])
      assert {:ok, [{1, _, {:ok, _}}, {2, _, {:ok, _}}]} = Seasons.payout_due()
      assert Economy.balance(a.id) == balances[a.id] + 1_000
      assert Economy.balance(b.id) == balances[b.id] + 500
      assert Economy.balance(c.id) == balances[c.id]

      assert {:ok, [{1, _, {:error, :already_claimed}}, {2, _, {:error, :already_claimed}}]} =
               Seasons.payout_due()

      assert [%{user_id: ^first, amount: 1_000}, %{amount: 500}] = Seasons.paid(last)
    end
  end
end
