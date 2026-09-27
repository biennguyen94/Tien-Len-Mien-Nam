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
    invalid_link: "Link không hợp lệ hoặc đã hết hạn",
    unknown_request: "Yêu cầu không hợp lệ"
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

  @doc "Card label, e.g. \"3♠\"."
  def card(%Card{} = card), do: Card.display(card)
end
