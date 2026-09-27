defmodule TienLenWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TienLenWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TienLenWeb.Endpoint

      use TienLenWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TienLenWeb.ConnCase
    end
  end

  setup tags do
    TienLen.DataCase.setup_sandbox(tags)
    {:ok, conn: sandbox_conn()}
  end

  @doc """
  A logged-in connection for the player called `name`. The user is registered on first use
  and reused for the same name within a test (so a player can "reopen" a page), and every
  call returns a fresh connection (a new tab or device).
  """
  def login_conn(name) do
    user =
      case Process.get({:test_user, name}) do
        nil ->
          slug =
            name |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "") |> String.slice(0, 8)

          username = "#{slug}_#{System.unique_integer([:positive])}" |> String.slice(0, 20)

          {:ok, user} =
            TienLen.Accounts.register_user(%{
              "display_name" => name,
              "username" => username,
              "password" => "mat-khau-123"
            })

          Process.put({:test_user, name}, user)
          user

        user ->
          user
      end

    sandbox_conn()
    |> Plug.Test.init_test_session(%{
      "user_id" => user.id,
      "live_socket_id" => "user_sessions:test-#{user.id}-#{System.unique_integer([:positive])}"
    })
  end

  @doc "The user behind `login_conn(name)` in this test."
  def test_user(name), do: Process.get({:test_user, name}) || raise("no test user #{name}")

  @doc """
  A new connection carrying the test's sandbox metadata in its user agent, so that the
  LiveViews it mounts can use the test's database connection. Use it instead of
  `build_conn/0` in tests that mount LiveViews.
  """
  def sandbox_conn do
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(TienLen.Repo, self())

    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("user-agent", Phoenix.Ecto.SQL.Sandbox.encode_metadata(metadata))
  end
end
