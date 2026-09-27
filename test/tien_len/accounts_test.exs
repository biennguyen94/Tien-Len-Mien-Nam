defmodule TienLen.AccountsTest do
  use TienLen.DataCase, async: true

  alias TienLen.Accounts
  alias TienLen.Accounts.User

  @valid %{display_name: "Bình", username: "binh_tran", password: "mat-khau-123"}

  describe "register_user/1 (Y1)" do
    test "stores a lowercase username, the display name and only a bcrypt hash" do
      {:ok, user} = Accounts.register_user(%{@valid | username: "  Binh_Tran "})
      assert user.username == "binh_tran"
      assert user.display_name == "Bình"
      assert user.password == nil
      assert user.hashed_password =~ ~r/^\$2b\$/
      refute user.hashed_password =~ "mat-khau-123"
      refute inspect(user) =~ user.hashed_password
    end

    test "usernames are unique regardless of case" do
      {:ok, _} = Accounts.register_user(@valid)
      {:error, cs} = Accounts.register_user(%{@valid | username: "BINH_TRAN"})
      assert "Tài khoản này đã có người dùng" in errors_on(cs).username
    end

    test "validates username format and length" do
      for bad <- ["ab", String.duplicate("a", 21), "an nguyen", "an-nguyen", "ănn", ""] do
        {:error, cs} = Accounts.register_user(%{@valid | username: bad})
        assert errors_on(cs)[:username], "#{inspect(bad)} should be refused"
      end

      for ok <- ["abc", "a.b_c", String.duplicate("z", 20), "user.123"] do
        assert {:ok, _} = Accounts.register_user(%{@valid | username: ok})
      end
    end

    test "validates password length (8 characters to 72 bytes)" do
      {:error, cs} = Accounts.register_user(%{@valid | password: "1234567"})
      assert "Mật khẩu phải có ít nhất 8 ký tự" in errors_on(cs).password

      # 25 × "ạ" = 75 bytes in UTF-8
      {:error, cs} = Accounts.register_user(%{@valid | password: String.duplicate("ạ", 25)})
      assert "Mật khẩu quá dài (tối đa 72 byte)" in errors_on(cs).password

      assert {:ok, _} = Accounts.register_user(%{@valid | password: String.duplicate("x", 72)})
    end

    test "validates the display name with the lobby rules" do
      {:error, cs} = Accounts.register_user(%{@valid | display_name: String.duplicate("a", 21)})
      assert errors_on(cs).display_name
      {:ok, user} = Accounts.register_user(%{@valid | display_name: "  An   Nguyễn "})
      assert user.display_name == "An Nguyễn"
    end

    test "all three fields are required" do
      {:error, cs} = Accounts.register_user(%{})
      assert Map.keys(errors_on(cs)) |> Enum.sort() == [:display_name, :password, :username]
    end
  end

  describe "authenticate/2" do
    setup do
      {:ok, user} = Accounts.register_user(@valid)
      %{user: user}
    end

    test "right username (any case) and password", %{user: user} do
      assert Accounts.authenticate("binh_tran", "mat-khau-123").id == user.id
      assert Accounts.authenticate(" BINH_TRAN ", "mat-khau-123").id == user.id
    end

    test "wrong password, unknown user, junk input" do
      assert Accounts.authenticate("binh_tran", "wrong-password") == nil
      assert Accounts.authenticate("nobody", "mat-khau-123") == nil
      assert Accounts.authenticate("binh_tran", "") == nil
      assert Accounts.authenticate(nil, nil) == nil
      assert Accounts.authenticate(%{}, 42) == nil
    end
  end

  describe "display name" do
    test "can be changed with the same rules" do
      {:ok, user} = Accounts.register_user(@valid)
      assert {:ok, %User{display_name: "Chi"}} = Accounts.change_display_name(user, "Chi")
      assert {:error, _} = Accounts.change_display_name(user, "")
    end
  end

  test "get_user/1 ignores junk ids" do
    assert Accounts.get_user(nil) == nil
    assert Accounts.get_user("1") == nil
    assert Accounts.get_user(-1) == nil
  end
end
