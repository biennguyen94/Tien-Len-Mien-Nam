defmodule TienLenWeb.PageController do
  use TienLenWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
