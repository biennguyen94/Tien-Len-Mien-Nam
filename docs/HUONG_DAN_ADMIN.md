# Hướng dẫn quản trị (admin)

Dành cho quản trị viên của Tiến Lên Miền Nam. Phần 1–8 là việc làm trên web. Phần 9 là vận hành máy chủ, cần quyền vào máy chạy Docker.
Luật chơi và cách tính coin cho người chơi xem ở [HUONG_DAN_NGUOI_CHOI.md](HUONG_DAN_NGUOI_CHOI.md).

---

## 1. Quyền admin

- Admin thấy nút **"Quản trị"** (chữ đỏ) trên thanh trên cùng, dẫn tới `/quan-tri`. Người chơi thường không thấy nút này và không vào được trang này.
- **Admin đầu tiên chỉ tạo được bằng lệnh trên máy chủ** (không có cách tự đăng ký làm admin):

  ```bash
  docker exec tien-len bin/tien_len rpc 'IO.inspect(TienLen.Admin.promote("tai_khoan"))'
  ```

  Tài khoản phải đăng ký trên web trước.
- Sau đó admin cấp quyền cho người khác ngay trên web: **Người chơi → chọn người → "Set admin"**. Chỉ admin mới làm được việc này.
- Các giới hạn an toàn:
  - không tự gỡ quyền admin của mình;
  - không gỡ được admin cuối cùng;
  - không khóa được chính mình hoặc một admin khác;
  - không tự cấm chat mình.
- **Mọi thao tác của admin đều được ghi vào "Nhật ký"**: ai làm, làm gì, với ai, lúc nào, lý do. Nhật ký chỉ ghi thêm, không sửa hay xóa được.
- Admin bị gỡ quyền hoặc bị khóa sẽ bị đẩy ra khỏi trang quản trị ngay lập tức.
- Admin cũng là một người chơi bình thường: vẫn chơi, có coin và xếp hạng.

---

## 2. Tổng quan (`/quan-tri`)

- **Tài khoản:** tổng số, số đăng ký hôm nay, số bị khóa, số admin.
- **Đang online:** số người đang mở ít nhất một trang.
- **Phòng đang mở:** số phòng, số phòng đang chơi, số người trong phòng.
- **Ván:** số ván hôm nay và 7 ngày qua (chỉ ván được ghi lại, không tính ván có máy).
- **Coin lưu hành:** tổng coin của mọi tài khoản.

---

## 3. Người chơi (`/quan-tri/nguoi-choi`)

- **Tìm** theo tài khoản hoặc tên hiển thị. Bấm vào một người để mở trang chi tiết.
- Trang chi tiết có: số coin, ngày tạo, hạng; 50 dòng lịch sử coin gần nhất; 20 ván gần đây. Các thao tác admin với người này xem ở trang **Nhật ký** (cột "Đối tượng").

| Nút / ô | Tác dụng |
|---|---|
| **Khóa** | Người chơi bị đăng xuất ngay trên mọi thiết bị, bị đưa ra khỏi mọi phòng (đang chơi thì bị loại khỏi ván), và không đăng nhập lại được ("Tài khoản đã bị khóa"). Coin và lịch sử giữ nguyên. |
| **Mở khóa** | Cho đăng nhập lại. |
| **Set admin / Gỡ admin** | Cấp hoặc gỡ quyền admin. |
| **Đặt lại mật khẩu** | Tạo mật khẩu tạm ngẫu nhiên, **chỉ hiện một lần**. Gửi cho người chơi qua kênh riêng và nhắc họ đổi mật khẩu ở sảnh. Mật khẩu tạm không được ghi vào nhật ký. |
| **Đổi tên** | Đổi tên hiển thị, ví dụ khi tên không phù hợp. Tài khoản đăng nhập không đổi. |
| **Điều chỉnh coin** | Nhập số, ví dụ `+500` hoặc `-200`, và **lý do (bắt buộc, 3–200 ký tự)**. Không trừ được quá số coin đang có. Người chơi thấy dòng "Quản trị viên điều chỉnh" trong Lịch sử coin, và số dư của họ cập nhật ngay. |
| **Cấm chat: 10 phút / 1 giờ / 24 giờ** | Người chơi không gửi được tin nhắn ở bất kỳ kênh chat nào, nhưng vẫn chơi bình thường. **"Bỏ cấm chat"** để kết thúc sớm. Nhãn "cấm chat đến …" cho biết thời hạn. |

Không có nút xóa tài khoản. Muốn chặn một người, hãy **Khóa**; như vậy lịch sử ván và sổ coin của những người khác vẫn đúng.

---

## 4. Phòng (`/quan-tri/phong`)

- Danh sách **mọi phòng đang mở**, kể cả phòng riêng tư (có nhãn "riêng tư"): mã phòng, chủ phòng, số người, mức cược, trạng thái.
- **Xem phòng** (`/quan-tri/phong/<mã>`):
  - thấy **bài trên tay của tất cả người chơi** và bài trên bàn (người chơi thường và khán giả không thấy được);
  - thấy chat phòng, và **✕** để xóa một tin nhắn (tin biến mất ngay với mọi người);
  - **"Mời ra"**: đưa một người (hoặc máy) ra khỏi phòng. Người đó không vào lại phòng này được. Nếu đang chơi, họ bị loại khỏi ván.
  - **"Đóng phòng"**: đóng phòng ngay. **Ván đang chơi bị hủy và không tính coin cho ván đó**, chỉ các chuỗi chặt heo đã tính xong ở các vòng trước là giữ nguyên. Ván cũng không được ghi vào bảng xếp hạng. Người chơi được đưa về sảnh kèm thông báo.

Hãy dùng quyền xem bài một cách có trách nhiệm: không báo bài cho ai. Mọi lần đóng phòng hay mời ra đều có trong nhật ký.

---

## 5. Ván (`/quan-tri/van`)

- 50 ván gần nhất: thời gian, phòng, người chơi, hạng, và **các khoản coin đã chuyển** trong ván (tiền hạng, chặt heo, thối heo, tới trắng).
- **"▶ Xem lại"**: xem lại từng nước với bài của mọi người. Chỉ có với ván được ghi sau khi tính năng xem lại được thêm vào.

---

## 6. Nhật ký (`/quan-tri/nhat-ky`)

- Toàn bộ thao tác của admin: cấp quyền (kể cả lệnh trên máy chủ), khóa/mở khóa, đổi tên, đặt lại mật khẩu, điều chỉnh coin, đóng phòng, mời ra, đổi cài đặt, thông báo, cấm/bỏ cấm chat, xóa tin nhắn.
- Khi xóa tin nhắn, nhật ký ghi tác giả và nơi (sảnh hay phòng), **không ghi nội dung tin nhắn** (tin nhắn không bao giờ được lưu).

---

## 7. Cài đặt (`/quan-tri/cai-dat`)

Giá trị mới **có hiệu lực ngay cho các lần sau**, không làm thay đổi lịch sử coin đã có.

| Cài đặt | Mặc định | Ghi chú |
|---|---|---|
| Coin tặng khi đăng ký | 1.000 | – |
| Thưởng ngày | 100 | mỗi ngày một lần |
| Cứu trợ | 500 | – |
| Cứu trợ khi dưới | 100 | chỉ nhận được cứu trợ khi số coin dưới mức này |
| Số phòng tối đa | 500 | chống tạo phòng hàng loạt |
| Nhiệm vụ: chơi 5 ván | 100 | – |
| Nhiệm vụ: về nhất 2 ván | 150 | – |
| Nhiệm vụ: chặt heo 1 lần | 200 | – |
| Thưởng tuần: hạng 1 / 2 / 3 | 1.000 / 500 / 300 | đặt 0 để tắt thưởng hạng đó |

- Để tắt một khoản thưởng, đặt nó về **0** (ví dụ khi thấy có người dùng nhiều tài khoản để "cày" nhiệm vụ).
- **Thông báo trên sảnh:**
  - nhập nội dung (tối đa 300 ký tự) rồi bấm "Cập nhật thông báo";
  - thông báo hiện ngay ở đầu mọi trang của mọi người;
  - để trống rồi lưu để tắt.

---

## 8. Chat và cộng đồng

- **Tin nhắn sảnh:** admin thấy nút **✕** cạnh mỗi tin trong "Chat sảnh" ngay trên trang sảnh.
- **Tin nhắn phòng:** xóa trong trang Xem phòng.
- **Tin nhắn riêng** giữa hai người **không được lưu**, nên admin không đọc được. Khi có người bị quấy rối, hãy cấm chat hoặc khóa người quấy rối.
- Không có bộ lọc từ tục (theo quyết định của chủ dự án).
- Chat không được lưu: khởi động lại máy chủ là mất hết, nên không còn bằng chứng sau đó. Nếu cần, hãy chụp màn hình trước khi xóa.
- Thưởng tuần được trả **tự động** trong vòng 1 giờ sau khi tuần kết thúc (thứ Hai 00:00 giờ Việt Nam), và mỗi hạng chỉ được trả một lần. Tab "Tuần trước" ở Bảng xếp hạng cho biết đã trao cho ai.

---

## 9. Vận hành máy chủ

Chi tiết kỹ thuật ở [DEPLOY.md](DEPLOY.md). Các lệnh thường dùng (chạy trong thư mục `deploy/` của mã nguồn):

```bash
docker compose ps                          # trạng thái (db healthy, tien-len Up)
docker compose logs -f tien-len            # xem log
docker compose up -d --build               # cập nhật sau khi có mã mới (tự chạy migration)
docker compose restart tien-len            # khởi động lại ứng dụng
docker compose down                        # dừng (giữ dữ liệu)
docker exec tien-len bin/tien_len rpc 'IO.inspect(TienLen.Admin.promote("tai_khoan"))'   # cấp admin
```

**⚠ Không bao giờ chạy `docker compose down -v`**: lệnh này xóa toàn bộ database (tài khoản, coin, lịch sử).

**Khởi động lại thì mất gì:**

| Mất | Còn nguyên |
|---|---|
| Ván đang chơi (không tính coin cho phần chưa xong) | Tài khoản, mật khẩu, coin, sổ coin |
| Phòng đang mở | Lịch sử ván, bảng xếp hạng, bản xem lại |
| Tin nhắn (sảnh, phòng, riêng) | Bạn bè, ảnh đại diện |
| Lời mời đang chờ, danh sách online | Cài đặt, thông báo |
| Bộ đếm đăng nhập sai, giới hạn tốc độ chat | Nhật ký admin, trạng thái khóa và cấm chat |

Nên báo trước bằng **Thông báo trên sảnh** trước khi khởi động lại hay cập nhật.

**Sao lưu và khôi phục:**

```bash
# sao lưu (chạy trong deploy/)
docker compose exec -T db pg_dump -U tien_len -d tien_len --clean --if-exists > tien_len_$(date +%F).sql

# khôi phục (dừng ứng dụng trước)
docker compose stop tien-len
docker compose exec -T db psql -U tien_len -d tien_len < tien_len_YYYY-MM-DD.sql
docker compose start tien-len
```

Giữ file sao lưu ở nơi an toàn, ngoài thư mục mã nguồn, vì file có chứa mật khẩu đã băm.

**Bảo mật:**
- File `deploy/.env` chứa khóa bí mật và mật khẩu database. Không chia sẻ file này và không đưa lên git (file đã được bỏ qua).
- Đổi `SECRET_KEY_BASE` thì mọi người bị đăng xuất; tài khoản không bị ảnh hưởng.
- `THROTTLE_BY_IP=false` trên máy WSL hiện tại. Khi chạy trên VPS sau proxy có IP thật, hãy bật lại thành `true` để chặn đăng nhập sai theo cả địa chỉ IP.
- Giữ ít admin, dùng mật khẩu mạnh. Admin xem được bài của mọi người và chỉnh được coin.

---

## 10. Xử lý tình huống thường gặp

| Tình huống | Cách làm |
|---|---|
| Người chơi quên mật khẩu | Người chơi → **Đặt lại mật khẩu** → gửi mật khẩu tạm qua kênh riêng → nhắc họ "đổi mật khẩu" ở sảnh. |
| Người chơi bị khóa vì nhập sai nhiều lần | Tự hết sau 15 phút. Khởi động lại ứng dụng cũng xóa bộ đếm. |
| Spam hoặc chửi bậy trong chat | Xóa tin (✕), rồi **Cấm chat** 10 phút, 1 giờ hoặc 24 giờ. Tái phạm thì **Khóa**. |
| Tên hiển thị không phù hợp | **Đổi tên**. |
| Phòng bị treo hoặc có người phá | **Mời ra**, hoặc **Đóng phòng** (ván bị hủy, không tính coin). |
| Mất coin do lỗi | Kiểm tra "Lịch sử coin" và trang Ván, rồi **Điều chỉnh coin** kèm lý do rõ ràng. |
| Nghi dùng nhiều tài khoản để cày thưởng | So sánh các ván ở trang Ván, xem lại ván. Có thể hạ thưởng nhiệm vụ hoặc thưởng tuần về 0, hoặc khóa tài khoản. |
| Cần thêm admin | Người đó đăng ký trước, rồi bạn bấm **Set admin** cho họ. |
