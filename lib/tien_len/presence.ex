defmodule TienLen.Presence do
  @moduledoc """
  Who is online and where (G6). Every open page of a logged-in player is tracked on the
  `"online"` topic under the user id, with `%{name, place, room_id}`; a player is online while
  at least one of their pages is. `place` is `"lobby"`, `"room"`, `"playing"` or `"other"`.

  In memory only (Phoenix.Presence over PubSub); nothing is written to the database.
  """

  use Phoenix.Presence, otp_app: :tien_len, pubsub_server: TienLen.PubSub

  @topic "online"
  # the most specific place wins when a player has several pages open
  @rank %{"playing" => 3, "room" => 2, "lobby" => 1, "other" => 0}

  def topic, do: @topic

  @doc "Subscribes the caller to presence diffs (`%Phoenix.Socket.Broadcast{event: \"presence_diff\"}`)."
  def subscribe, do: Phoenix.PubSub.subscribe(TienLen.PubSub, @topic)

  @doc "Tracks the page process `pid` of `user`."
  def track_page(pid, user, place \\ "other", room_id \\ nil) do
    track(pid, @topic, key(user.id), %{name: user.display_name, place: place, room_id: room_id})
  end

  @doc "Moves an already tracked page to another place."
  def move(pid, user, place, room_id \\ nil) do
    update(pid, @topic, key(user.id), %{name: user.display_name, place: place, room_id: room_id})
  end

  @doc "Online players as `[%{id, name, place, room_id}]`, sorted by name."
  def online_users do
    @topic
    |> list()
    |> Enum.map(fn {key, %{metas: metas}} ->
      meta = Enum.max_by(metas, &Map.get(@rank, &1.place, 0))
      %{id: String.to_integer(key), name: meta.name, place: meta.place, room_id: meta.room_id}
    end)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
  end

  @doc "The online entry of one player, or `nil`."
  def get_user(user_id) do
    case get_by_key(@topic, key(user_id)) do
      [] ->
        nil

      %{metas: metas} ->
        meta = Enum.max_by(metas, &Map.get(@rank, &1.place, 0))
        %{id: user_id, name: meta.name, place: meta.place, room_id: meta.room_id}
    end
  end

  def online?(user_id), do: get_user(user_id) != nil

  @doc "Number of players online."
  def count, do: @topic |> list() |> map_size()

  defp key(id), do: to_string(id)
end
