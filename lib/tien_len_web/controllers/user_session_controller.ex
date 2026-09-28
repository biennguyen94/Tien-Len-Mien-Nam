defmodule TienLenWeb.UserSessionController do
  @moduledoc """
  Login (`POST /dang-nhap`) and logout (`DELETE /dang-xuat`). Registration is handled by the
  lobby LiveView, which then submits the same credentials here to log the new user in.
  """

  use TienLenWeb, :controller

  alias TienLen.Accounts
  alias TienLenWeb.UserAuth

  def create(conn, %{"user" => %{"username" => username, "password" => password} = params}) do
    # F8; IP counting can be turned off (tests share 127.0.0.1)
    ip = if Application.get_env(:tien_len, :throttle_by_ip, true), do: conn.remote_ip

    with :ok <- TienLen.LoginThrottle.check(username, ip),
         %Accounts.User{} = user <- Accounts.authenticate(username, password) do
      if Accounts.User.locked?(user) do
        conn |> put_flash(:error, "Tài khoản đã bị khóa") |> redirect(to: ~p"/")
      else
        TienLen.LoginThrottle.success(username)
        conn |> put_flash(:info, welcome(params, user)) |> UserAuth.log_in_user(user)
      end
    else
      {:error, :throttled} ->
        conn
        |> put_flash(:error, "Đăng nhập sai quá nhiều lần. Thử lại sau 15 phút.")
        |> redirect(to: ~p"/")

      nil ->
        TienLen.LoginThrottle.failure(username, ip)

        # same message whether the account exists or not
        conn
        |> put_flash(:error, "Sai tài khoản hoặc mật khẩu")
        |> put_flash(:login_username, String.slice(to_string(username), 0, 20))
        |> redirect(to: ~p"/")
    end
  end

  def create(conn, _params) do
    conn |> put_flash(:error, "Sai tài khoản hoặc mật khẩu") |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    # flash first: log_out_user/1 sends the redirect
    conn |> put_flash(:info, "Đã đăng xuất") |> UserAuth.log_out_user()
  end

  defp welcome(%{"registered" => "true"}, user),
    do: "Đăng ký thành công. Chào #{user.display_name}!"

  defp welcome(_params, user), do: "Chào #{user.display_name}!"
end
