defmodule TienLenWeb.Text do
  @moduledoc """
  Vietnamese UI strings (decision O4): error reasons from the domain, combination names and
  instant-win hand names.
  """

  alias TienLen.Card

  @reasons %{
    empty: "Hãy chọn lá bài",
    duplicate_cards: "Lá bài bị trùng",
    invalid_combination: "Bộ bài không hợp lệ",
    does_not_match: "Không cùng loại với bài trên bàn",
    too_low: "Chưa đủ lớn để chặn",
    cannot_chop: "Không được chặt bằng bộ này",
    must_include_card: "Nước đầu phải có lá bắt buộc",
    cannot_pass_on_lead: "Đang đi đầu, không được bỏ lượt",
    not_four_pair: "Chỉ bốn đôi thông mới chặt ngoài lượt được",
    no_chop_target: "Không có gì để chặt",
    game_over: "Ván đã kết thúc",
    not_in_game: "Bạn không có trong ván này",
    not_active: "Bạn đã xong ván này",
    not_your_turn: "Chưa đến lượt bạn",
    not_your_cards: "Bạn không có những lá này",
    not_host: "Chỉ chủ phòng mới được bắt đầu",
    not_enough_players: "Cần ít nhất 2 người",
    game_in_progress: "Ván đang diễn ra",
    room_full: "Phòng đã đủ 4 người",
    room_not_found: "Phòng không tồn tại",
    not_in_room: "Bạn không ở trong phòng này",
    invalid_name: "Tên không hợp lệ (1–20 ký tự)",
    no_game: "Chưa có ván nào",
    unknown_command: "Lệnh không hợp lệ",
    too_many_rooms: "Máy chủ đang quá nhiều phòng, hãy thử lại sau",
    unknown_request: "Yêu cầu không hợp lệ",
    not_enough_coins: "Cần ít nhất 2 người có đủ 10× tiền cược",
    invalid_stake: "Tiền cược phải là 0 hoặc từ 10 trở lên",
    already_claimed: "Hôm nay bạn đã nhận rồi",
    not_eligible: "Chỉ nhận được cứu trợ khi số coin còn quá ít",
    not_found: "Không tìm thấy",
    forbidden: "Bạn không có quyền làm việc này",
    already_admin: "Người này đã là admin",
    not_admin: "Người này không phải admin",
    cannot_demote_self: "Không thể tự gỡ quyền admin của mình",
    last_admin: "Không thể gỡ admin cuối cùng",
    cannot_lock_self: "Không thể tự khóa tài khoản của mình",
    cannot_lock_admin: "Không thể khóa tài khoản admin",
    already_locked: "Tài khoản đã bị khóa từ trước",
    not_locked: "Tài khoản không bị khóa",
    insufficient_coins: "Không đủ coin để trừ",
    invalid_amount: "Số coin không hợp lệ",
    reason_required: "Hãy ghi lý do (3–200 ký tự)",
    kicked: "Bạn đã bị mời ra khỏi phòng này",
    announcement_too_long: "Thông báo tối đa 300 ký tự",
    wrong_password: "Mật khẩu hiện tại không đúng",
    throttled: "Đăng nhập sai quá nhiều lần. Thử lại sau 15 phút.",
    invalid_message: "Tin nhắn phải có 1–200 ký tự",
    muted: "Bạn đang bị cấm chat",
    chat_too_fast: "Bạn gửi tin quá nhanh, chờ vài giây",
    invalid_target: "Chỉ ném được vào ghế có người khác",
    throw_too_fast: "Từ từ, 3 giây mới ném được một lần",
    cannot_afford: "Bạn không đủ coin",
    already_owned: "Bạn đã có món này rồi",
    not_owned: "Bạn chưa mua món này",
    not_online: "Người này không online",
    invites_off: "Người này không nhận lời mời",
    invite_pending: "Người này đang có lời mời khác",
    target_busy: "Người này đang ở trong phòng",
    invite_too_fast: "Bạn mời quá nhiều, chờ một chút",
    invite_expired: "Lời mời đã hết hạn",
    not_enough_coins_to_join: "Bạn không đủ coin cho mức cược của phòng này",
    cannot_mute_self: "Không thể tự cấm chat mình",
    not_muted: "Người này không bị cấm chat",
    invalid_duration: "Thời hạn không hợp lệ",
    bots_need_free_room: "Máy chơi chỉ có ở phòng chơi vui (cược 0)",
    cannot_friend_self: "Không thể kết bạn với chính mình",
    already_friends: "Hai bạn đã là bạn bè",
    request_pending: "Đã gửi lời mời kết bạn, đang chờ trả lời",
    too_many_friends: "Danh sách bạn bè đã đầy (tối đa 200)",
    too_many_requests: "Bạn đang có quá nhiều lời mời kết bạn chưa được trả lời (tối đa 20)",
    friend_too_fast: "Bạn gửi lời mời kết bạn quá nhanh, chờ một chút",
    mission_not_done: "Nhiệm vụ chưa hoàn thành",
    unknown_mission: "Không có nhiệm vụ này",
    invalid_avatar: "Ảnh đại diện không hợp lệ",
    season_not_over: "Mùa giải chưa kết thúc",
    too_many_spectators: "Phòng đã đủ 20 người xem"
  }

  @types %{
    single: "Lá lẻ",
    pair: "Đôi",
    triple: "Sám",
    straight: "Sảnh",
    four_of_a_kind: "Tứ quý",
    three_pair: "Ba đôi thông",
    four_pair: "Bốn đôi thông"
  }

  @instant %{
    four_twos: "Tứ quý heo",
    six_pairs: "Sáu đôi",
    dragon: "Sảnh rồng",
    four_threes: "Tứ quý 3"
  }

  @doc "Message for an error reason (or `{:error, reason}`)."
  def reason({:error, reason}), do: reason(reason)
  def reason(reason) when is_atom(reason), do: Map.get(@reasons, reason, "Có lỗi xảy ra")

  @doc "All known reasons (used in tests to check every domain reason has a message)."
  def known_reasons, do: Map.keys(@reasons)

  @doc "Name of a combination type."
  def combo_type(type), do: Map.fetch!(@types, type)

  @doc "Name of an instant-win hand."
  def instant(type), do: Map.fetch!(@instant, type)

  @doc "Place label: 1 → \"Nhất\" … 4 → \"Bét\" (for 4 players the last is \"Bét\")."
  def place(1, _n), do: "Nhất"
  def place(n, n), do: "Bét"
  def place(2, _n), do: "Nhì"
  def place(3, _n), do: "Ba"

  @coin_reasons %{
    "registration" => "Tặng khi đăng ký",
    "starting_grant" => "Tặng ban đầu",
    "daily_bonus" => "Thưởng ngày",
    "relief" => "Cứu trợ",
    "place" => "Tiền hạng",
    "instant_win" => "Tới trắng",
    "chop" => "Chặt heo",
    "thoi" => "Thối heo",
    "admin_adjust" => "Quản trị viên điều chỉnh",
    "mission" => "Nhiệm vụ ngày",
    "season_reward" => "Thưởng mùa giải",
    "throw" => "Ném đồ",
    "shop" => "Mua ở cửa hàng"
  }

  @doc "A player's avatar (P3), or the default face."
  def avatar(nil), do: "🙂"
  def avatar(%{avatar: avatar}), do: avatar(avatar)
  def avatar(avatar) when is_binary(avatar), do: avatar
  def avatar(_), do: "🙂"

  @doc "Label of a ledger reason."
  def coin_reason(reason), do: Map.get(@coin_reasons, reason, reason)

  @doc "Coins with Vietnamese thousands separators: 1234567 → \"1.234.567\"."
  def coins(nil), do: "—"

  def coins(n) when is_integer(n) do
    sign = if n < 0, do: "-", else: ""

    digits =
      n
      |> abs()
      |> Integer.to_string()
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(".", &Enum.join/1)
      |> String.reverse()

    sign <> digits
  end

  @doc "Signed coins: +500 / -250 / 0."
  def signed_coins(n) when is_integer(n) and n > 0, do: "+" <> coins(n)
  def signed_coins(n), do: coins(n)

  @doc "Card label, e.g. \"3♠\"."
  def card(%Card{} = card), do: Card.display(card)
end
