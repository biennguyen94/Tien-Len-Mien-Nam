defmodule TienLenWeb.PlayerHook do
  @moduledoc """
  `on_mount` hook: puts the player's identity from the (signed) session into LiveView assigns
  (`:player_id`, `:player_name`). The id is set by `TienLenWeb.PlayerIdentity` on the first
  HTTP request; the name by `TienLenWeb.PlayerController`.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    case session do
      %{"player_id" => id} when is_binary(id) ->
        {:cont,
         socket
         |> assign(:player_id, id)
         |> assign(:player_name, session["player_name"])}

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end
end
