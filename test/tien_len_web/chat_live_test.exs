defmodule TienLenWeb.ChatLiveTest do
  @moduledoc "Phases 24–27 in the browser: room / lobby / private chat, online list, invites, private rooms, return after login, admin moderation."
  use TienLenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TienLen.{Accounts, Admin, Lobby, RoomServer}

  defp open_room!(opts \\ []) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  defp admin_conn(name) do
    conn = login_conn(name)
    {:ok, _} = Admin.promote(test_user(name).username)
    conn
  end

  describe "room chat (G3, G4)" do
    test "seated players chat, with quick phrases, also during a game" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

      an |> form("#room-chat-form", %{"text" => "chào <b>Bình</b>"}) |> render_submit()
      assert has_element?(binh, "#room-chat", "chào <b>Bình</b>")
      refute render(binh) =~ "<b>Bình</b>"

      binh |> element("#room-chat button", "Chúc may mắn!") |> render_click()
      assert has_element?(an, "#room-chat", "Binh:")
      assert has_element?(an, "#room-chat", "Chúc may mắn!")

      an |> element("#start") |> render_click()
      an |> form("#room-chat-form", %{"text" => "đánh nhanh nào"}) |> render_submit()
      assert has_element?(binh, "#room-chat", "đánh nhanh nào")

      # a newcomer page (reload) sees the history
      {:ok, binh2, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
      assert has_element?(binh2, "#room-chat", "đánh nhanh nào")
    end

    test "errors are shown: empty text, too fast" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      an |> form("#room-chat-form", %{"text" => "  "}) |> render_submit()
      assert render(an) =~ "Tin nhắn phải có 1–200 ký tự"
      for _ <- 1..5, do: an |> form("#room-chat-form", %{"text" => "x"}) |> render_submit()
      an |> form("#room-chat-form", %{"text" => "x"}) |> render_submit()
      assert render(an) =~ "Bạn gửi tin quá nhanh"
    end

    test "admins see and delete room messages in the watch view (G12)" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      an |> form("#room-chat-form", %{"text" => "tin xấu"}) |> render_submit()

      {:ok, watch, _} = live(admin_conn("Boss"), ~p"/quan-tri/phong/#{id}")
      assert has_element?(watch, "#watch-chat", "tin xấu")
      watch |> element("#watch-chat button[title='Xóa tin nhắn']") |> render_click()
      refute has_element?(watch, "#watch-chat", "tin xấu")
      refute has_element?(an, "#room-chat", "tin xấu")
    end
  end

  describe "lobby (G5, G6, G9)" do
    test "lobby chat live; admins delete; players cannot" do
      {:ok, an, _} = live(login_conn("An"), ~p"/")
      {:ok, boss, _} = live(admin_conn("Boss"), ~p"/")

      an |> form("#lobby-chat-form", %{"text" => "ai chơi không"}) |> render_submit()
      assert has_element?(boss, "#lobby-chat", "ai chơi không")
      refute has_element?(an, "#lobby-chat button[title='Xóa tin nhắn']")

      [msg_id] =
        Regex.run(~r/id="lobby-chat-msg-(\d+)"[^>]*>(?:(?!<\/li>).)*ai chơi không/s, render(an),
          capture: :all_but_first
        )

      render_hook(an, "lobby_chat_delete", %{"id" => msg_id})
      assert render(an) =~ "Bạn không có quyền"
      assert has_element?(an, "#lobby-chat", "ai chơi không")

      boss |> element("#lobby-chat-msg-#{msg_id} button") |> render_click()
      refute has_element?(an, "#lobby-chat", "ai chơi không")
    end

    test "online list with places; a muted player's message is refused" do
      {:ok, an, _} = live(login_conn("An"), ~p"/")
      {:ok, _binh, _} = live(login_conn("Binh"), ~p"/")
      binh = test_user("Binh")
      assert has_element?(an, "#online-#{binh.id}", "Ở sảnh")

      id = open_room!()
      {:ok, _table, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
      assert has_element?(an, "#online-#{binh.id}", "Trong phòng")

      _ = admin_conn("Boss")
      {:ok, _} = Admin.mute(test_user("Boss").id, test_user("An").id, 10)
      an |> form("#lobby-chat-form", %{"text" => "hello"}) |> render_submit()
      assert render(an) =~ "Bạn đang bị cấm chat"
    end

    test "\"Không nhận lời mời\" is saved on the account" do
      {:ok, an, _} = live(login_conn("An"), ~p"/")
      an |> element("#toggle-invites") |> render_click()
      refute Accounts.get_user(test_user("An").id).accept_invites
      an |> element("#toggle-invites") |> render_click()
      assert Accounts.get_user(test_user("An").id).accept_invites
    end
  end

  describe "private chat (G7)" do
    test "open from the online list, send, unread badge, read" do
      {:ok, an, _} = live(login_conn("An"), ~p"/")
      {:ok, binh, _} = live(login_conn("Binh"), ~p"/")
      binh_id = test_user("Binh").id

      an |> element("#online-#{binh_id} button", "Nhắn") |> render_click()
      assert has_element?(an, "#social-peer", "Binh")
      an |> form("#private-form", %{"text" => "vào phòng mình nhé"}) |> render_submit()
      assert has_element?(an, "#private-lines", "vào phòng mình nhé")

      assert has_element?(binh, "#social-unread", "1")
      binh |> element("#social-toggle") |> render_click()
      binh |> element("#conv-#{test_user("An").id} button") |> render_click()
      assert has_element?(binh, "#private-lines", "vào phòng mình nhé")
      refute has_element?(binh, "#social-unread")
    end

    test "the panel's online tab works on the table page too" do
      id = open_room!()
      {:ok, table, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, _binh, _} = live(login_conn("Binh"), ~p"/")
      table |> element("#social-toggle") |> render_click()
      table |> element("#social-online-tab") |> render_click()
      assert has_element?(table, "#social-online", "Binh")
    end
  end

  describe "invites (G8, G10)" do
    test "invite from the table; popup on the lobby; accept goes to the room" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(login_conn("Binh"), ~p"/")
      binh_id = test_user("Binh").id

      an |> element("#toggle-invite") |> render_click()
      an |> element("#candidate-#{binh_id} button", "Mời") |> render_click()
      assert render(an) =~ "Đã mời Binh"

      assert has_element?(binh, "#invite-popup", "An")
      binh |> element("#invite-accept") |> render_click()
      assert_redirect(binh, "/phong/#{id}")
      assert render(an) =~ "Binh đã nhận lời mời"
    end

    test "decline closes the popup and tells the inviter" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(login_conn("Binh"), ~p"/")

      {:ok, _} = TienLen.Invites.invite(test_user("An").id, test_user("Binh").id, id)
      assert has_element?(binh, "#invite-popup")
      binh |> element("#invite-decline") |> render_click()
      refute has_element?(binh, "#invite-popup")
      assert render(an) =~ "Binh đã từ chối lời mời"
    end

    test "players with invites off are greyed out, without a button" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, _binh, _} = live(login_conn("Binh"), ~p"/")
      {:ok, _} = Accounts.set_accept_invites(test_user("Binh"), false)

      an |> element("#toggle-invite") |> render_click()
      assert has_element?(an, "#candidate-#{test_user("Binh").id}", "không nhận lời mời")
      refute has_element?(an, "#candidate-#{test_user("Binh").id} button")
    end

    test "the copy-link button carries the full room URL" do
      id = open_room!()
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      assert has_element?(an, "#copy-link[data-url$='/phong/#{id}'][phx-hook=CopyLink]")
    end

    test "a room link opened logged out comes back to the room after login" do
      id = open_room!()
      next = "/phong/#{id}"
      assert {:error, {:redirect, %{to: to}}} = live(sandbox_conn(), next)
      assert to == "/?" <> URI.encode_query(next: next)

      {:ok, lobby, _} = live(sandbox_conn(), to)
      assert has_element?(lobby, "#login-form input[name='user[next]'][value='#{next}']")

      _ = login_conn("An")
      creds = %{"username" => test_user("An").username, "password" => "mat-khau-123"}
      conn = post(sandbox_conn(), ~p"/dang-nhap", %{"user" => Map.put(creds, "next", next)})
      assert redirected_to(conn) == next

      for bad <- ["https://evil.example", "//evil.example", "/quan-tri", "/phong/../x"] do
        conn = post(sandbox_conn(), ~p"/dang-nhap", %{"user" => Map.put(creds, "next", bad)})
        assert redirected_to(conn) == "/"
      end

      conn =
        post(sandbox_conn(), ~p"/dang-nhap", %{
          "user" => %{creds | "password" => "sai-sai-sai"} |> Map.put("next", next)
        })

      assert redirected_to(conn) == to
    end
  end

  describe "private rooms (G11)" do
    test "created private: hidden from other lobbies; host can switch while waiting" do
      {:ok, an_lobby, _} = live(login_conn("An"), ~p"/")
      {:ok, binh_lobby, _} = live(login_conn("Binh"), ~p"/")

      an_lobby
      |> form("#create-room-form", %{"room" => %{"stake" => "0", "private" => "true"}})
      |> render_submit()

      {path, _flash} = assert_redirect(an_lobby)
      "/phong/" <> id = path
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      {:ok, table, _} = live(login_conn("An"), path)
      assert has_element?(table, "#private-badge")
      refute has_element?(binh_lobby, "#room-#{id}")

      table |> element("#toggle-private") |> render_click()
      refute has_element?(table, "#private-badge")
      assert has_element?(binh_lobby, "#room-#{id}")
    end
  end

  describe "admin (G6, G12)" do
    test "dashboard shows players online; the user page mutes and unmutes" do
      {:ok, _an, _} = live(login_conn("An"), ~p"/")
      conn = admin_conn("Boss")
      {:ok, dash, _} = live(conn, ~p"/quan-tri")
      assert has_element?(dash, "#stat-online")

      {:ok, page, _} = live(conn, ~p"/quan-tri/nguoi-choi/#{test_user("An").id}")
      page |> element("#mute-60") |> render_click()
      assert has_element?(page, "#muted-badge")
      page |> element("#unmute") |> render_click()
      refute has_element?(page, "#muted-badge")
      assert Enum.map(Admin.actions(2), & &1.action) == ["unmute", "mute"]
    end
  end
end
