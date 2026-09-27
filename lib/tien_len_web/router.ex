defmodule TienLenWeb.Router do
  use TienLenWeb, :router

  import TienLenWeb.UserAuth, only: [fetch_current_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TienLenWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TienLenWeb do
    pipe_through :browser

    post "/dang-nhap", UserSessionController, :create
    delete "/dang-xuat", UserSessionController, :delete

    # lobby: logged in or not (shows the register / login forms when not)
    live_session :public, on_mount: {TienLenWeb.UserAuth, :mount_current_user} do
      live "/", LobbyLive
    end

    # rooms: login required (A3)
    live_session :authenticated, on_mount: {TienLenWeb.UserAuth, :require_user} do
      live "/phong/:id", TableLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", TienLenWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:tien_len, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TienLenWeb.Telemetry
    end
  end
end
