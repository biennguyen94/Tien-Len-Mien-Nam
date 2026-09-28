defmodule TienLen.Chat do
  @moduledoc """
  Room, lobby and private chat (decisions CH1–CH4, interpretations G1–G7, G12).

  Messages live **in memory only** (CH2): room chat in the room process (last 50), lobby chat
  in `TienLen.Chat.Lobby` (last 100), private chat in `TienLen.Chat.Private` (last 20 per
  pair, dropped after 1 h without messages). Nothing is written to the database.

  Every send goes through `prepare/2`:
  - the text is trimmed, whitespace collapsed, 1–#{200} characters (G2);
  - the sender is re-read from the database: locked → `:forbidden`, muted → `:muted` (G12);
  - at most 5 messages per 10 s per player, across all chats (G2);
  - the name shown is the account's display name, never a client value.

  No profanity filter (CH3). HEEx escapes the text; links stay plain text.
  """

  alias TienLen.{Accounts, Presence, RateLimit, RoomServer}
  alias TienLen.Accounts.User
  alias TienLen.Chat.{Lobby, Private}

  @max_length 200
  @rate_limit 5
  @rate_window 10_000

  # G3
  @phrases [
    "Nhanh lên!",
    "Hay quá!",
    "Chúc may mắn!",
    "Cảm ơn!",
    "Xin lỗi, mạng lag",
    "Ván này căng!",
    "Chơi lại không?",
    "Hẹn gặp lại!"
  ]

  @type message :: %{
          id: pos_integer(),
          user_id: integer(),
          name: String.t(),
          text: String.t(),
          at: DateTime.t()
        }

  @doc "The quick phrases (G3)."
  def phrases, do: @phrases

  @doc "Normalises a message text (G2)."
  @spec normalize(term()) :: {:ok, String.t()} | {:error, :invalid_message}
  def normalize(text) when is_binary(text) do
    if String.valid?(text) do
      text = text |> String.replace(~r/[[:cntrl:]]/u, " ") |> String.replace(~r/\s+/u, " ")
      text = String.trim(text)
      len = String.length(text)
      if len >= 1 and len <= @max_length, do: {:ok, text}, else: {:error, :invalid_message}
    else
      {:error, :invalid_message}
    end
  end

  def normalize(_), do: {:error, :invalid_message}

  @doc "Validates the text and the sender, then builds the message (see the moduledoc)."
  @spec prepare(integer(), term()) :: {:ok, message()} | {:error, atom()}
  def prepare(user_id, text) do
    with {:ok, text} <- normalize(text),
         {:ok, user} <- sender(user_id),
         :ok <- rate(user.id) do
      {:ok,
       %{
         id: System.unique_integer([:positive, :monotonic]),
         user_id: user.id,
         name: user.display_name,
         text: text,
         at: DateTime.utc_now(:second)
       }}
    end
  end

  defp sender(user_id) do
    case Accounts.get_active_user(user_id) do
      nil -> {:error, :forbidden}
      user -> if User.muted?(user), do: {:error, :muted}, else: {:ok, user}
    end
  end

  defp rate(user_id) do
    case RateLimit.hit({:chat, user_id}, @rate_limit, @rate_window) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :chat_too_fast}
    end
  end

  # -- room (G4) --------------------------------------------------------------------

  @doc "Sends to a room's chat; only seated players may (G4)."
  def send_room(room_id, user_id, text) do
    with {:ok, msg} <- prepare(user_id, text), do: RoomServer.chat(room_id, user_id, msg)
  end

  @doc "A room's chat history (oldest first) for a seated player."
  def room_history(room_id, user_id), do: RoomServer.chat_history(room_id, user_id)

  # -- lobby (G5) -------------------------------------------------------------------

  def lobby_topic, do: Lobby.topic()
  def subscribe_lobby, do: Phoenix.PubSub.subscribe(TienLen.PubSub, Lobby.topic())

  @doc "Sends to the lobby chat."
  def send_lobby(user_id, text) do
    with {:ok, msg} <- prepare(user_id, text), do: Lobby.post(msg)
  end

  def lobby_history, do: Lobby.history()

  # -- private (G7) -----------------------------------------------------------------

  @doc "Sends a private line; the recipient must be online right now (G7)."
  def send_private(from_id, to_id, text) do
    case from_id != to_id && Presence.get_user(to_id) do
      false -> {:error, :not_found}
      nil -> {:error, :not_online}
      peer -> with {:ok, msg} <- prepare(from_id, text), do: Private.post(to_id, peer.name, msg)
    end
  end

  defdelegate conversation(user_id, peer_id), to: Private
  defdelegate conversations(user_id), to: Private
  defdelegate mark_read(user_id, peer_id), to: Private
end
