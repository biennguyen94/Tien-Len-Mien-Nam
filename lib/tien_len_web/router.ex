defmodule TienLenWeb.Router do
  use TienLenWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TienLenWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TienLenWeb.PlayerIdentity
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TienLenWeb do
    pipe_through :browser

    post "/ten", PlayerController, :set_name

    live_session :player, on_mount: TienLenWeb.PlayerHook do
      live "/", LobbyLive
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
