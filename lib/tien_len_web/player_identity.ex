defmodule TienLenWeb.PlayerIdentity do
  @moduledoc """
  Anonymous player identity (decision O3).

  - Every browser session gets a random **player id**, stored in the Phoenix session cookie.
    The cookie is signed, so a client cannot change it to impersonate another player.
    Plugged into the `:browser` pipeline; LiveViews read it from their session
    (`session["player_id"]`).
  - The display name is kept in the session too (`"player_name"`), set by the lobby.
  - A **seat token** (`sign/1`, `verify/1`) is a `Phoenix.Token` carrying the player id. It lets
    a player prove who they are over a channel that has no session (e.g. a reconnect link).
    Tokens expire after #{div(30 * 24 * 3600, 86_400)} days.
  """

  @behaviour Plug

  import Plug.Conn

  @salt "tien_len player seat token"
  @max_age 30 * 24 * 3600

  @doc "A fresh random player id."
  @spec new_player_id() :: String.t()
  def new_player_id, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  @doc "Signs a seat token for `player_id`."
  @spec sign(String.t()) :: String.t()
  def sign(player_id), do: Phoenix.Token.sign(TienLenWeb.Endpoint, @salt, player_id)

  @doc "Verifies a seat token: `{:ok, player_id}` or `{:error, :invalid | :expired | :missing}`."
  @spec verify(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, atom()}
  def verify(token, opts \\ []) do
    Phoenix.Token.verify(TienLenWeb.Endpoint, @salt, token,
      max_age: Keyword.get(opts, :max_age, @max_age)
    )
  end

  # -- Plug ---------------------------------------------------------------------

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_session(conn, "player_id") do
      id when is_binary(id) ->
        assign_identity(conn, id)

      _ ->
        id = new_player_id()
        conn |> put_session("player_id", id) |> assign_identity(id)
    end
  end

  defp assign_identity(conn, id) do
    conn
    |> assign(:player_id, id)
    |> assign(:player_name, get_session(conn, "player_name"))
  end
end
