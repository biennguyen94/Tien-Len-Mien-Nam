defmodule TienLen.LoginThrottleTest do
  @moduledoc "F8: 5 failures per username or IP within 15 minutes block further logins."
  use ExUnit.Case, async: true

  alias TienLen.LoginThrottle

  defp uniq, do: "user_#{System.unique_integer([:positive])}"

  defp ip,
    do:
      {10, 0, rem(System.unique_integer([:positive]), 250),
       rem(System.unique_integer([:positive]), 250)}

  @min 60_000

  test "the 6th attempt after 5 failures of one username is refused, until the window passes" do
    user = uniq()
    t0 = 1_000_000_000

    for i <- 0..4 do
      assert LoginThrottle.check(user, nil, t0 + i) == :ok
      LoginThrottle.failure(user, nil, t0 + i)
    end

    assert LoginThrottle.check(user, nil, t0 + 10) == {:error, :throttled}
    assert LoginThrottle.check(String.upcase(user), nil, t0 + 10) == {:error, :throttled}
    assert LoginThrottle.check(user, nil, t0 + 15 * @min - 1) == {:error, :throttled}
    assert LoginThrottle.check(user, nil, t0 + 15 * @min + 5) == :ok
  end

  test "failures from one IP block every username from that IP" do
    addr = ip()
    t0 = 2_000_000_000
    for i <- 0..4, do: LoginThrottle.failure(uniq(), addr, t0 + i)
    assert LoginThrottle.check(uniq(), addr, t0 + 10) == {:error, :throttled}
    assert LoginThrottle.check(uniq(), ip(), t0 + 10) == :ok
  end

  test "a success clears the username counter" do
    user = uniq()
    t0 = 3_000_000_000
    for i <- 0..3, do: LoginThrottle.failure(user, nil, t0 + i)
    LoginThrottle.success(user)
    LoginThrottle.failure(user, nil, t0 + 5)
    assert LoginThrottle.check(user, nil, t0 + 6) == :ok
  end
end
