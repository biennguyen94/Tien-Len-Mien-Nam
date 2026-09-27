defmodule TienLenWeb.PlayerController do
  @moduledoc """
  Stores the display name in the session (LiveViews cannot write the session).
  """

  use TienLenWeb, :controller

  alias TienLen.Lobby

  def set_name(conn, params) do
    return_to = safe_return_to(params["return_to"])

    case Lobby.normalize_name(params["name"]) do
      {:ok, name} ->
        conn |> put_session("player_name", name) |> redirect(to: return_to)

      {:error, reason} ->
        conn |> put_flash(:error, TienLenWeb.Text.reason(reason)) |> redirect(to: return_to)
    end
  end

  # Only local paths, to avoid open redirects.
  defp safe_return_to("/" <> rest = path) when is_binary(rest) do
    if String.starts_with?(path, "//"), do: "/", else: path
  end

  defp safe_return_to(_), do: "/"
end
