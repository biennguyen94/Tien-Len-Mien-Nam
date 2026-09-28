defmodule TienLen.Settings do
  @moduledoc """
  Settings editable by admins (AD9, F7): the economy values and the lobby announcement.

  Values live in the `settings` table and are cached in `:persistent_term`, so reading them is
  cheap and needs no database access (rooms and pure code read them freely). `put/2` writes
  the database first, then the cache, and broadcasts `{:settings_changed, key, value}`.
  The cache is filled from the database at start (`load/0`); a missing key uses its default.
  """

  import Ecto.Query
  alias TienLen.Repo

  @economy %{
    "starting_coins" => 1_000,
    "daily_bonus" => 100,
    "relief" => 500,
    "relief_below" => 100,
    "max_rooms" => 500,
    # daily missions (M1) and weekly season rewards (S2)
    "mission_play_reward" => 100,
    "mission_win_reward" => 150,
    "mission_chop_reward" => 200,
    "season_reward_1" => 1_000,
    "season_reward_2" => 500,
    "season_reward_3" => 300
  }

  @doc "Economy keys with their defaults (the decided values C2 and the room cap)."
  def economy_defaults, do: @economy

  def topic, do: "settings"
  def subscribe, do: Phoenix.PubSub.subscribe(TienLen.PubSub, topic())

  @doc "Integer setting (economy)."
  def int(key) when is_map_key(@economy, key) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil -> default_int(key)
      value -> value
    end
  end

  # max_rooms keeps honouring the application env (MAX_ROOMS in prod, tests)
  defp default_int("max_rooms"),
    do: Application.get_env(:tien_len, :max_rooms, @economy["max_rooms"])

  defp default_int(key), do: @economy[key]

  @doc "The lobby announcement, or nil."
  def announcement, do: :persistent_term.get({__MODULE__, "announcement"}, nil)

  @doc "Saves a validated value (string for the announcement, integer otherwise)."
  def put(key, value) do
    Repo.insert_all(
      "settings",
      [
        %{
          key: key,
          value: encode(value),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ],
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    cache(key, value)
    Phoenix.PubSub.broadcast(TienLen.PubSub, topic(), {:settings_changed, key, value})
    :ok
  end

  @doc "Clears a setting (back to its default)."
  def delete(key) do
    Repo.delete_all(from s in "settings", where: s.key == ^key)
    :persistent_term.erase({__MODULE__, key})
    Phoenix.PubSub.broadcast(TienLen.PubSub, topic(), {:settings_changed, key, nil})
    :ok
  end

  @doc "Fills the cache from the database (called at application start)."
  def load do
    for {key, value} <- Repo.all(from s in "settings", select: {s.key, s.value}) do
      cache(key, decode(key, value))
    end

    :ok
  end

  defp cache(key, nil), do: :persistent_term.erase({__MODULE__, key})
  defp cache(key, value), do: :persistent_term.put({__MODULE__, key}, value)

  defp encode(value) when is_integer(value), do: Integer.to_string(value)
  defp encode(value) when is_binary(value), do: value

  defp decode("announcement", value), do: value
  defp decode(_key, value), do: String.to_integer(value)
end
