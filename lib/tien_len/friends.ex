defmodule TienLen.Friends do
  @moduledoc """
  Friends (decisions FR1–FR5).

  One `friendships` row per pair: `user_id` asked `friend_id`; `status` is `"pending"` until
  the other accepts, then `"accepted"`. A request to someone who already asked you accepts
  theirs. At most #{200} friends and #{20} requests waiting for an answer; 10 requests per
  minute. Both players get `{:friends_changed}` on their user topic after every change.
  """

  import Ecto.Query

  alias TienLen.{Accounts, RateLimit, Repo}
  alias TienLen.Accounts.User
  alias TienLen.Friends.Friendship

  @max_friends 200
  @max_pending 20

  @doc "Sends a friend request (or accepts theirs if they asked first)."
  def request(user_id, friend_id) do
    with :ok <- if(user_id == friend_id, do: {:error, :cannot_friend_self}, else: :ok),
         %User{} <- Accounts.get_active_user(friend_id) || {:error, :not_found},
         :ok <- rate(user_id) do
      case relation(user_id, friend_id) do
        :friends -> {:error, :already_friends}
        :outgoing -> {:error, :request_pending}
        :incoming -> accept(user_id, friend_id)
        :none -> create(user_id, friend_id)
      end
    end
  end

  defp create(user_id, friend_id) do
    cond do
      count_friends(user_id) >= @max_friends ->
        {:error, :too_many_friends}

      Repo.aggregate(
        from(f in Friendship, where: f.user_id == ^user_id and f.status == "pending"),
        :count
      ) >=
          @max_pending ->
        {:error, :too_many_requests}

      true ->
        case Repo.insert(%Friendship{user_id: user_id, friend_id: friend_id},
               on_conflict: :nothing
             ) do
          {:ok, %{id: nil}} -> {:error, :request_pending}
          {:ok, _} -> notify([user_id, friend_id], {:ok, :requested})
          {:error, _} -> {:error, :not_found}
        end
    end
  end

  @doc "Accepts the request `requester_id` sent to `user_id`."
  def accept(user_id, requester_id) do
    with :ok <-
           if(count_friends(user_id) >= @max_friends, do: {:error, :too_many_friends}, else: :ok) do
      case pending(requester_id, user_id)
           |> Repo.update_all(set: [status: "accepted", updated_at: now()]) do
        {1, _} -> notify([user_id, requester_id], {:ok, :accepted})
        _ -> {:error, :not_found}
      end
    end
  end

  @doc "Declines a request sent to `user_id`."
  def decline(user_id, requester_id),
    do: delete(pending(requester_id, user_id), [user_id, requester_id])

  @doc "Withdraws a request `user_id` sent."
  def cancel(user_id, friend_id), do: delete(pending(user_id, friend_id), [user_id, friend_id])

  @doc "Ends a friendship (either side)."
  def remove(user_id, friend_id) do
    from(f in Friendship,
      where:
        f.status == "accepted" and
          ((f.user_id == ^user_id and f.friend_id == ^friend_id) or
             (f.user_id == ^friend_id and f.friend_id == ^user_id))
    )
    |> delete([user_id, friend_id])
  end

  defp delete(query, ids) do
    case Repo.delete_all(query) do
      {n, _} when n > 0 -> notify(ids, :ok)
      _ -> {:error, :not_found}
    end
  end

  defp pending(from_id, to_id),
    do:
      from(f in Friendship,
        where: f.user_id == ^from_id and f.friend_id == ^to_id and f.status == "pending"
      )

  @doc "`:self`, `:friends`, `:outgoing` (I asked), `:incoming` (they asked) or `:none`."
  def relation(user_id, other_id) when user_id == other_id, do: :self

  def relation(user_id, other_id) do
    rows =
      Repo.all(
        from f in Friendship,
          where:
            (f.user_id == ^user_id and f.friend_id == ^other_id) or
              (f.user_id == ^other_id and f.friend_id == ^user_id),
          select: {f.user_id, f.status}
      )

    cond do
      Enum.any?(rows, &(elem(&1, 1) == "accepted")) -> :friends
      Enum.any?(rows, &(&1 == {user_id, "pending"})) -> :outgoing
      rows != [] -> :incoming
      true -> :none
    end
  end

  @doc "Friends of a user: `[%User{}]` sorted by display name."
  def friends(user_id) do
    Repo.all(
      from u in User,
        join: f in Friendship,
        on:
          f.status == "accepted" and
            ((f.user_id == ^user_id and f.friend_id == u.id) or
               (f.friend_id == ^user_id and f.user_id == u.id)),
        order_by: [u.display_name, u.id]
    )
  end

  @doc "Ids of a user's friends."
  def friend_ids(user_id), do: user_id |> friends() |> MapSet.new(& &1.id)

  @doc "Requests waiting for `user_id`'s answer (the requesters)."
  def incoming(user_id) do
    Repo.all(
      from u in User,
        join: f in Friendship,
        on: f.user_id == u.id and f.friend_id == ^user_id and f.status == "pending",
        order_by: [desc: f.inserted_at]
    )
  end

  @doc "Requests `user_id` sent that are not answered yet."
  def outgoing(user_id) do
    Repo.all(
      from u in User,
        join: f in Friendship,
        on: f.friend_id == u.id and f.user_id == ^user_id and f.status == "pending",
        order_by: [desc: f.inserted_at]
    )
  end

  def incoming_count(user_id),
    do:
      Repo.aggregate(
        from(f in Friendship, where: f.friend_id == ^user_id and f.status == "pending"),
        :count
      )

  defp count_friends(user_id) do
    Repo.aggregate(
      from(f in Friendship,
        where: f.status == "accepted" and (f.user_id == ^user_id or f.friend_id == ^user_id)
      ),
      :count
    )
  end

  defp rate(user_id) do
    case RateLimit.hit({:friend, user_id}, 10, 60_000) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :friend_too_fast}
    end
  end

  defp notify(ids, result) do
    for id <- ids,
        do:
          Phoenix.PubSub.broadcast(
            TienLen.PubSub,
            TienLen.Admin.user_topic(id),
            {:friends_changed}
          )

    result
  end

  defp now, do: DateTime.utc_now(:second)
end
