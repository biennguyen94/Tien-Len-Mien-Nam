defmodule TienLen.DataCase do
  @moduledoc """
  Tests that use the database. Each test runs in a sandbox transaction that is rolled back;
  `async: true` tests get their own connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias TienLen.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import TienLen.DataCase
    end
  end

  setup tags do
    TienLen.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc "Checks out a sandbox connection owned by the test process."
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TienLen.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc "Changeset errors as a map of field => [message]."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
