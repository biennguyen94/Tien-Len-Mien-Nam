defmodule TienLen.RepoTest do
  use TienLen.DataCase, async: true

  test "the test database is reachable and is the dedicated one, never OpenMU's" do
    assert %{rows: [[1]]} = Repo.query!("select 1")
    assert %{rows: [[db]]} = Repo.query!("select current_database()")
    assert db =~ ~r/^tien_len_test/
    refute db == "openmu"
    assert Repo.config()[:port] in [nil, 5434] or System.get_env("TEST_DATABASE_URL")
  end
end
