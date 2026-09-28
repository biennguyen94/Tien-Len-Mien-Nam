# Các lệnh hữu ích khi học Phoenix và web API

Sổ tay các lệnh **đã dùng thật** khi nghiên cứu repo gốc và xây dựng project này (Phase 1 → 38), kèm giải thích cho người mới.

- Mọi ví dụ đều chạy được trong repo `Tien-Len-Mien-Nam`.
- Lệnh chạy từ thư mục gốc của repo, trừ khi có ghi `cd deploy`.
- `S=/tmp/thu-nghiem` là một thư mục nháp tùy ý, dùng để chứa file tạm.

Mục lục:
1. [Chuẩn bị môi trường](#1-chuẩn-bị-môi-trường)
2. [Shell: những ký hiệu phải biết](#2-shell-những-ký-hiệu-phải-biết)
3. [Tìm hiểu một project có sẵn](#3-tìm-hiểu-một-project-có-sẵn)
4. [Mix: công cụ trung tâm của Elixir](#4-mix-công-cụ-trung-tâm-của-elixir)
5. [Tạo project Phoenix và bản release](#5-tạo-project-phoenix-và-bản-release)
6. [Chạy ứng dụng Phoenix](#6-chạy-ứng-dụng-phoenix)
7. [IEx và `mix run`: thử code nhanh](#7-iex-và-mix-run-thử-code-nhanh)
8. [Database: Ecto và PostgreSQL](#8-database-ecto-và-postgresql)
9. [Test](#9-test)
10. [Thử web và API bằng curl](#10-thử-web-và-api-bằng-curl)
11. [Docker và môi trường production](#11-docker-và-môi-trường-production)
12. [Tìm kiếm, đọc và sửa file nhanh](#12-tìm-kiếm-đọc-và-sửa-file-nhanh)
13. [Git](#13-git)
14. [Quy trình mẫu](#14-quy-trình-mẫu)

---

## 1. Chuẩn bị môi trường

```bash
# Elixir/Erlang cài trong thư mục người dùng; shell không đăng nhập (script, tool) cần thêm PATH:
export PATH="$HOME/.local/beam/otp/bin:$HOME/.local/beam/elixir/bin:$PATH"

elixir --version          # phiên bản Erlang/OTP và Elixir
mix --version
node --version; npm --version   # khi làm việc với project JavaScript (như repo gốc)
which gcc make                  # có trình biên dịch C chưa (một số thư viện như bcrypt cần)
ls ~/.mix/archives              # các archive đã cài, ví dụ phx_new (bộ tạo project Phoenix)
```

- **Erlang/OTP** là máy ảo (BEAM) và thư viện nền. **Elixir** là ngôn ngữ chạy trên đó. **Phoenix** là web framework viết bằng Elixir.
- Gặp `command not found: mix` thì gần như luôn là do thiếu PATH.

**Tạo bí mật:**

```bash
mix phx.gen.secret                # khóa ký cookie phiên (SECRET_KEY_BASE)
openssl rand -hex 24              # chuỗi ngẫu nhiên 48 ký tự hex, dùng làm mật khẩu database
chmod 600 deploy/.env             # file bí mật: chỉ chủ máy đọc được

# Thêm một biến vào .env chỉ khi chưa có (chạy lại nhiều lần vẫn an toàn)
grep -q '^POSTGRES_PASSWORD=' deploy/.env || printf '\nPOSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)" >> deploy/.env
```

---

## 2. Shell: những ký hiệu phải biết

Hầu hết các lệnh trong tài liệu này ghép nhiều lệnh nhỏ lại với nhau. Hiểu các ký hiệu dưới đây là đọc được hết:

| Ký hiệu | Nghĩa | Ví dụ |
|---|---|---|
| `a \| b` | Output của `a` thành input của `b` | `mix test \| tail -3` |
| `2>&1` | Gộp luồng lỗi (stderr) vào output (stdout) để `grep` / `tail` đọc được cả hai | `mix test 2>&1 \| grep Failed` |
| `> file` / `>> file` | Ghi đè / ghi thêm output vào file | `mix phx.server > $S/phx.log 2>&1` |
| `a && b` | Chạy `b` **chỉ khi** `a` thành công | `mix format && mix test` |
| `a \|\| b` | Chạy `b` **chỉ khi** `a` thất bại | `grep -q X f \|\| echo "không có"` |
| `a; b` | Chạy lần lượt, không quan tâm kết quả | `sleep 1; tail -3 log` |
| `$(lệnh)` | Thay bằng output của lệnh | `kill $(cat $S/phx.pid)` |
| `&` | Chạy nền, không chờ | `mix phx.server &` |
| `$!` | PID của lệnh nền vừa chạy | `echo $! > $S/phx.pid` |
| `$RANDOM` | Số ngẫu nhiên | `mix test --seed $RANDOM` |
| `<<'EOF' … EOF` | Heredoc: đưa nhiều dòng làm input (dấu nháy đơn: không thay biến bên trong) | `cat > f.exs <<'EOF'` |
| `for i in $(seq 1 10); do …; done` | Lặp 10 lần | xem mục 9.3 |
| `f() { …; }` | Định nghĩa hàm shell để dùng lại | `tok() { grep … "$1"; }` |
| `yes n \| lệnh` | Tự trả lời "n" cho mọi câu hỏi y/n của lệnh | `yes n \| mix phx.gen.release` |
| `set -e` | Trong script: dừng ngay khi có lệnh lỗi | – |

```bash
# Chờ một điều kiện (tối đa 60 giây), không dùng sleep cố định:
for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:4010/ && break; sleep 1; done

# Đếm số lần thất bại trong vòng lặp
fails=0; for i in $(seq 1 20); do lệnh || fails=$((fails+1)); done; echo "fail: $fails/20"
```

---

## 3. Tìm hiểu một project có sẵn

Đây là cách repo gốc `nguyenank/tien-len` được nghiên cứu ở Phase 1 **mà không sửa gì trong nó**.

### 3.1 Nhìn tổng quan

```bash
cd /home/bien_nguyen/tien-len
git log --oneline | head -20           # 20 commit gần nhất
git status --short                     # có file nào đang sửa dở không
git remote -v                          # repo này lấy từ đâu

# Liệt kê mọi file, bỏ qua node_modules và .git
find . -path ./node_modules -prune -o -path ./.git -prune -o -type f -print | sort

cat package.json                       # thư viện và script (JavaScript)
cat mix.exs                            # tương đương với project Elixir

# Đọc hàng loạt file kèm số dòng
for f in server.js src/TienLen.js src/moves/*.js; do echo "======== $f"; cat -n $f; done
```

### 3.2 Đào lịch sử bằng git

```bash
git log --format='%h %ad %s' --date=short | head      # commit kèm ngày
git show f2ab344 --stat                                # một commit sửa những file nào
git show 6b677ec^:src/moves/cardAreaMoves.js           # nội dung file NGAY TRƯỚC commit 6b677ec
git log --format=%h -S"relocateCards" -- src/moves     # commit nào thêm/xóa chữ "relocateCards"
git log --oneline -- src/tests                         # lịch sử của riêng một thư mục
git -C /đường/dẫn/repo log --oneline | head            # chạy git ở thư mục khác, không cần cd

# Wiki của GitHub cũng là một repo git
git clone -q https://github.com/nguyenank/tien-len.wiki.git $S/wiki && cat $S/wiki/Rules.md
```

`git log -S` ("pickaxe") rất mạnh: nó tìm ra lúc một hàm hay một chuỗi xuất hiện hoặc biến mất.

### 3.3 Chạy thử code gốc trên một BẢN SAO

Không cài đặt hay chạy thử trong repo gốc. Copy ra thư mục nháp rồi làm ở đó:

```bash
S=/tmp/thu-nghiem; mkdir -p $S
rsync -a --exclude .git /home/bien_nguyen/tien-len/ $S/tl/     # copy, bỏ .git
cd $S/tl

# Cài đúng phiên bản thư viện, không ghi vào package.json (--no-save)
npm install --no-audit --no-fund --ignore-scripts --no-save --legacy-peer-deps \
  boardgame.io@0.39.16 jest@26 babel-jest@26 @babel/core @babel/preset-env

# Chạy test Jest và chỉ giữ dòng kết quả (✓ pass, ✕ fail)
npx jest src/tests 2>&1 | grep -E "✓|✕|Tests:|Suites:"
npx jest -c jest.scratch.config.js --verbose                  # dùng file cấu hình riêng
npx jest -c jest.scratch.config.js src/tests/probe.test.js -t "seed"   # chỉ test có tên chứa "seed"
```

Mẹo khi nghiên cứu:
- Viết **test "thăm dò" (probe)** trên bản sao để chứng minh một giả thuyết. Ví dụ ở Phase 1, test như vậy đã chứng minh server gốc làm lộ seed xáo bài và log nước đi cho client.
- Đọc thẳng mã nguồn của thư viện trong `node_modules`:

  ```bash
  grep '"version"' node_modules/boardgame.io/package.json
  grep -n "STRIP_SECRETS" -A14 node_modules/boardgame.io/dist/cjs/core.js
  ```

---

## 4. Mix: công cụ trung tâm của Elixir

`mix` giống `npm` + `make` gộp lại: tạo project, tải thư viện, biên dịch, chạy test, chạy tác vụ.

```bash
mix help                  # liệt kê mọi tác vụ
mix help test             # tài liệu một tác vụ (các cờ của mix test…)
mix help phx              # các tác vụ của Phoenix

mix deps.get              # tải thư viện trong mix.exs (giống npm install)
mix deps.unlock --unused  # bỏ thư viện không còn dùng khỏi mix.lock

mix compile                             # biên dịch
mix compile --warnings-as-errors        # coi cảnh báo là lỗi: giữ code sạch
mix compile --force                     # biên dịch lại tất cả
rm -rf _build/test                      # xóa bản build của môi trường test (khi build bị lỗi lạ)

mix format                              # tự định dạng code theo chuẩn (.formatter.exs)
mix format --check-formatted            # chỉ kiểm tra, không sửa (dùng trong CI)
```

**`mix precommit`** là alias do project định nghĩa trong `mix.exs`. **Chạy lệnh này trước mỗi commit.**

```elixir
# mix.exs
precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
```

**`MIX_ENV`** chọn môi trường: `dev` (mặc định), `test`, `prod`. Mỗi môi trường có config riêng: `config/dev.exs`, `config/test.exs`, `config/runtime.exs` (đọc biến môi trường lúc chạy production).

```bash
MIX_ENV=test mix ecto.migrate     # chạy migration cho database test
MIX_ENV=prod mix release          # đóng gói bản production (Dockerfile làm việc này)
```

---

## 5. Tạo project Phoenix và bản release

```bash
# Tạo project vào thư mục nháp để xem trước những gì sẽ được sinh ra
cd $S && mix phx.new tien_len --app tien_len --module TienLen --no-ecto --no-mailer --no-install
#   --no-ecto: chưa dùng database   --no-mailer: không gửi mail   --no-install: chưa tải thư viện

# Chép sang repo thật, bỏ những file không muốn ghi đè
rsync -a --exclude .git --exclude README.md --exclude .gitignore $S/tien_len/ /home/bien_nguyen/Tien-Len-Mien-Nam/

# Sinh file cho bản release và Dockerfile (yes n = không ghi đè file đã có)
yes n | mix phx.gen.release --docker
#   tạo Dockerfile, .dockerignore, rel/overlays/bin/server, rel/overlays/bin/migrate, lib/tien_len/release.ex
```

- **Release** là bản đóng gói chạy độc lập, không cần Elixir trên máy chạy.
- Bên trong container, các lệnh vận hành đều nằm dưới `bin/`: `bin/server`, `bin/migrate`, `bin/tien_len rpc|remote|start`.

---

## 6. Chạy ứng dụng Phoenix

```bash
mix assets.setup          # tải tailwind/esbuild (chỉ cần lần đầu)
mix setup                 # deps.get + tạo database + migrate + assets

mix phx.server            # chạy server dev (project này dùng cổng 4010)
iex -S mix phx.server     # chạy server VÀ mở IEx để gõ lệnh vào app đang chạy (khuyên dùng)
PORT=4011 mix phx.server  # đổi cổng tạm thời
```

**Chạy server ở chế độ nền để thử bằng curl** (cách dùng suốt project):

```bash
ss -ltn | grep ':4010 ' && echo "cổng 4010 đang bận"          # kiểm tra cổng trước khi chạy

nohup mix phx.server > $S/phx.log 2>&1 & echo $! > $S/phx.pid  # chạy nền, ghi log, lưu PID
for i in $(seq 1 60); do curl -s -o /dev/null http://localhost:4010/ && break; sleep 1; done   # chờ server lên

# … thử bằng curl (mục 10) …
grep -iE "\[error\]|warning" $S/phx.log | head                 # server có báo lỗi không
kill $(cat $S/phx.pid)                                          # tắt server nền
```

- `nohup` giữ tiến trình chạy tiếp dù terminal đóng.
- `ss -ltn` liệt kê các cổng đang lắng nghe. Trên máy này cổng 4000 đã bị `openmu-web` dùng, nên project chuyển sang 4010.

**Xem toàn bộ route** (URL nào đi vào LiveView hay controller nào):

```bash
mix phx.routes
#   POST    /dang-nhap          TienLenWeb.UserSessionController :create
#   GET     /                   TienLenWeb.LobbyLive nil
#   GET     /phong/:id          TienLenWeb.TableLive nil
```

**Công cụ khi chạy dev:**
- LiveDashboard ở `http://localhost:4010/dev/dashboard`: xem tiến trình, bộ nhớ, request, truy vấn.
- Debug LiveView trong DevTools → Console:

  ```js
  liveSocket.enableDebug()           // in mọi sự kiện LiveView gửi/nhận
  liveSocket.enableLatencySim(1000)  // giả lập mạng chậm 1 giây
  liveSocket.disableLatencySim()
  ```

---

## 7. IEx và `mix run`: thử code nhanh

### 7.1 IEx

IEx là shell tương tác của Elixir. Chạy `iex -S mix` (không server) hoặc `iex -S mix phx.server`.

```elixir
h Enum.map                 # xem tài liệu một hàm
h TienLen.Hint.moves       # tài liệu module của chính project
i "xin chào"               # thông tin về một giá trị (kiểu dữ liệu…)
recompile()                # biên dịch lại sau khi sửa code, không cần thoát IEx

# Gọi thẳng code của app
TienLen.Card.parse_many!("3S 4H 5D") |> TienLen.Combination.classify()
TienLen.Accounts.get_by_username("bien")

# Truy vấn database bằng Ecto
import Ecto.Query
TienLen.Repo.all(from u in TienLen.Accounts.User, select: {u.username, u.coins})
TienLen.Repo.aggregate(TienLen.Stats.GameRecord, :count)

# Soi tiến trình: mỗi phòng chơi là một GenServer
TienLen.Lobby.list_rooms()
pid = TienLen.RoomServer.whereis("abc123")
Process.alive?(pid)
:sys.get_state(pid)        # xem toàn bộ state bên trong một GenServer (chỉ để debug!)

:observer.start()          # giao diện đồ họa xem cây tiến trình (cần môi trường có GUI)
```

### 7.2 `mix run`: chạy một đoạn code trong app rồi thoát

Tiện để thử nghiệm mà không cần mở IEx:

```bash
# Một đoạn ngắn
mix run -e 'IO.inspect(TienLen.Card.parse_many!("3S 3C") |> TienLen.Combination.classify())'

# Thí nghiệm: 2000 bộ bài ngẫu nhiên có seed, đếm mỗi loại bộ xuất hiện bao nhiêu lần
mix run -e '
alias TienLen.{Card, Combination}
freq = for seed <- 1..2000, reduce: %{} do acc ->
  s = :rand.seed_s(:exsss, seed); {st, s} = :rand.uniform_s(12, s); {len, _} = :rand.uniform_s(6, s)
  hand = for r <- (st + 2)..(st + len + 1)//1, r <= 15, do: Card.new(r, :spades)
  t = case Combination.classify(hand) do {:ok, c} -> c.type; {:error, e} -> e end
  Map.update(acc, t, 1, &(&1 + 1))
end
IO.inspect(freq)'

# Một script dài hơn: ghi ra file .exs rồi chạy (ví dụ: chơi thử một ván, in bảng xếp hạng)
mix run $S/play_one.exs 2>&1 | grep -vE "^\s*$|\[info\]|\[debug\]"
```

- `:rand.seed_s(:exsss, seed)` tạo bộ sinh số ngẫu nhiên **có seed**: cùng seed thì cùng kết quả. Nhờ vậy thí nghiệm và test lặp lại được y hệt.
- `grep -v` bỏ bớt các dòng log `[info]`, `[debug]` cho dễ đọc.
- `elixir -e 'IO.puts 1 + 1'` chạy Elixir thuần, không nạp app.

---

## 8. Database: Ecto và PostgreSQL

### 8.1 PostgreSQL cho dev/test bằng Docker

```bash
docker compose -f deploy/docker-compose.dev.yml up -d     # bật (cổng 127.0.0.1:5434)
docker compose -f deploy/docker-compose.dev.yml ps        # trạng thái
docker compose -f deploy/docker-compose.dev.yml down      # tắt, dữ liệu vẫn giữ

# Chờ PostgreSQL sẵn sàng rồi mới làm tiếp
for i in $(seq 1 30); do docker exec tien-len-dev-db pg_isready -U tien_len >/dev/null 2>&1 && break; sleep 1; done
docker exec tien-len-dev-db psql -U tien_len -tc 'select version();'

ss -ltn | grep -E ':(5432|5433|5434) '   # các cổng PostgreSQL đang dùng (5433 là của OpenMU: đừng đụng vào)
```

### 8.2 Migration

Migration là "lịch sử thay đổi cấu trúc database".

```bash
mix ecto.create                          # tạo database
MIX_ENV=test mix ecto.create
mix ecto.gen.migration add_avatar        # tạo file priv/repo/migrations/<thời gian>_add_avatar.exs
mix ecto.migrate                         # chạy các migration chưa chạy
mix ecto.rollback                        # lùi migration cuối (khi viết sai)
mix ecto.migrations                      # migration nào đã (up) / chưa (down) chạy
mix ecto.reset                           # XÓA database rồi tạo lại (chỉ dùng ở dev!)
MIX_ENV=test mix ecto.migrate            # database test có migration riêng
```

Một migration mẫu trong project:

```elixir
def change do
  alter table(:users) do
    add :avatar, :string
  end

  create table(:friendships) do
    add :user_id, references(:users, on_delete: :delete_all), null: false
    add :friend_id, references(:users, on_delete: :delete_all), null: false
    add :status, :string, null: false, default: "pending"
    timestamps type: :utc_datetime
  end

  create unique_index(:friendships, [:user_id, :friend_id])
  create constraint(:friendships, :not_self, check: "user_id <> friend_id")
end
```

Lỗi hay gặp:
- `relation ... already exists`: migration tạo lại thứ đã có (ví dụ một index). Sửa migration rồi chạy lại. Trong PostgreSQL, migration chạy trong transaction, nên một migration lỗi không làm dở dang database.
- Test báo thiếu cột hoặc bảng: quên chạy `MIX_ENV=test mix ecto.migrate`.
- App chạy nhưng thiếu bảng mới ở dev: quên `mix ecto.migrate` (xem bằng `mix ecto.migrations`).

### 8.3 Vào thẳng PostgreSQL bằng psql

```bash
docker exec -it tien-len-dev-db psql -U tien_len -d tien_len_dev          # dev
docker exec -it tien-len-db psql -U tien_len -d tien_len                  # production

# Chạy một câu rồi thoát (-t: bỏ tiêu đề; -c: câu lệnh)
docker exec tien-len-db psql -U tien_len -d tien_len -tc "select username, role, coins from users order by id"
docker exec tien-len-db psql -U tien_len -d tien_len -c '\d users' | grep -E "coins|coins_not_negative"
```

Trong psql:

```sql
\dt                         -- liệt kê bảng
\d users                    -- cấu trúc một bảng (cột, index, constraint)
select column_name from information_schema.columns where table_name = 'users';
select reason, sum(amount) from coin_transactions group by reason;          -- thống kê sổ coin
select u.username, (select string_agg(reason || ':' || amount, ', ')
                    from coin_transactions t where t.user_id = u.id) from users u;   -- sổ coin từng người
\q                          -- thoát
```

---

## 9. Test

### 9.1 Các lệnh cơ bản

```bash
mix test                                         # chạy toàn bộ
mix test test/tien_len/bot_test.exs              # một file
mix test test/tien_len/bot_test.exs:57           # chỉ test ở dòng 57
mix test test/tien_len test/tien_len_web/live    # nhiều thư mục
mix test --failed                                # chỉ chạy lại các test vừa fail
mix test --max-failures 1                        # dừng ở lỗi đầu tiên
mix test --trace                                 # in tên từng test, chạy tuần tự (dễ thấy test treo)
mix test --seed 836046                           # chạy lại đúng thứ tự ngẫu nhiên cũ
mix test --only integration                      # chỉ test có @tag :integration
mix test --only describe:"random simulations"    # chỉ các test trong một khối describe
mix test --exclude slow                          # bỏ test có @tag :slow
mix test --cover                                 # đo độ phủ code
```

**Seed:** ExUnit trộn thứ tự test ngẫu nhiên và in `Running ExUnit with seed: 836046`. Khi một test chỉ thỉnh thoảng fail, dùng đúng seed đó với `--seed` để tái hiện.

### 9.2 Lọc output cho gọn

```bash
mix test 2>&1 | tail -3                          # chỉ dòng kết quả, ví dụ:
#   Finished in 0.06 seconds (0.06s async, 0.00s sync)
#   Result: 15 passed (1 doctest, 14 tests)          ← có test fail thì thêm dòng "Failed: n tests"

# Test nào fail và vì sao
mix test 2>&1 | grep -E "^\s+[0-9]+\) test|Assertion|code:|left:|right:|\*\* \(|Result|Failed"

# Toàn bộ chi tiết của lỗi đầu tiên (14 dòng sau dòng "  1)")
mix test --failed 2>&1 | grep -A14 "^  1)"

# Bỏ stacktrace và dòng trống
mix test test/tien_len/game_test.exs 2>&1 | grep -vE "^\s+at |^\s*$"
```

`left:` / `right:` là hai vế của một `assert ... == ...` bị sai.

### 9.3 Săn test "lúc pass lúc fail" (flaky)

```bash
# a) Chạy 10 lần, chỉ in dòng kết quả và tên test fail
for i in $(seq 1 10); do mix test 2>&1 | grep -E "^Result|\) test"; done

# b) Đếm số lần fail của một file nghi ngờ (dòng "  1) test ..." chỉ xuất hiện khi có test fail)
fails=0; for i in $(seq 1 20); do
  mix test test/tien_len/room_server_test.exs 2>&1 | grep -q "^  [0-9]*) test" && fails=$((fails+1))
done; echo "fail: $fails/20"

# c) Seed ngẫu nhiên mỗi lần; gặp lỗi thì in seed + chi tiết rồi dừng
for i in $(seq 1 25); do
  out=$(mix test --seed $RANDOM 2>&1)
  if echo "$out" | grep -qE "\) test"; then
    echo "$out" | grep seed; echo "$out" | grep -A30 "^  1)"; break
  fi
done; echo "dừng ở lần $i"

# d) Chạy nền thật lâu, ghi lỗi vào log, trong lúc đó vẫn làm việc khác
cat > $S/flaky.sh <<'EOF'
cd /home/bien_nguyen/Tien-Len-Mien-Nam
for i in $(seq 1 60); do
  out=$(mix test 2>&1)
  if echo "$out" | grep -qE "\) test"; then
    { echo "lần $i"; echo "$out" | grep seed; echo "$out" | grep -A40 "^  1)"; } >> /tmp/flaky.log; exit 0
  fi
done
echo "không lỗi trong 60 lần" >> /tmp/flaky.log
EOF
nohup bash $S/flaky.sh > /dev/null 2>&1 &
cat /tmp/flaky.log                              # xem kết quả sau
pgrep -fa "flaky.sh|mix test"                   # còn đang chạy không?
pkill -f flaky.sh; pkill -f "mix test"          # dừng hẳn
```

Các nguyên nhân flaky đã gặp trong project này:
- **Dữ liệu ngẫu nhiên**: bài chia ngẫu nhiên đôi khi ra tới trắng làm ván kết thúc ngay. Sửa bằng dữ liệu cố định (`deals: [...]`).
- **Chờ bằng `Process.sleep(20)`** trong khi server xử lý không đồng bộ. Sửa bằng cách chờ đến khi điều kiện đúng:

  ```elixir
  defp eventually(fun, tries \\ 100) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(10) && eventually(fun, tries - 1)
    end
  end

  assert eventually(fn -> RoomServer.view(id, :a).spectators == 0 end)
  ```

- **Timer quá ngắn** khi máy tải nặng (40 ms → 500 ms).
- **Tiến trình chết** làm `GenServer.call` crash bên gọi. Sửa bằng `catch :exit`. Đây là **lỗi thật** mà test flaky đã giúp tìm ra.

### 9.4 Thống kê tạm bằng một bản sao của test

Khi muốn biết một mô phỏng trong test thực sự làm được gì, mà không sửa test thật:

```bash
mkdir -p test/tmp_stats
sed 's/# the bot must actually exercise every kind of event/IO.inspect(kinds, label: "SIM")/;
     s/defmodule TienLen.GameTest/defmodule TienLen.GameStatsTmp/' \
  test/tien_len/game_test.exs > test/tmp_stats/stats_test.exs
mix test test/tmp_stats/stats_test.exs --only describe:"random simulations" 2>&1 | grep SIM
rm -rf test/tmp_stats                             # dọn ngay, không để lọt vào commit
```

### 9.5 Các mẫu viết test Phoenix

```elixir
# LiveView: mở trang, bấm nút, gửi form, kiểm tra HTML
{:ok, view, _html} = live(conn, ~p"/phong/#{id}")
view |> element("#start") |> render_click()
view |> form("#room-chat-form", %{"text" => "xin chào"}) |> render_submit()
view |> form("#search-form", %{"q" => "zed"}) |> render_change()
render_hook(view, "lobby_chat_delete", %{"id" => "1"})    # giả lập sự kiện "tự chế" từ client lạ
assert has_element?(view, "#room-chat", "xin chào")
assert_redirect(view, "/")

# Trang bị chặn khi chưa đăng nhập
assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/quan-tri")

# Controller (POST form)
conn = post(conn, ~p"/dang-nhap", %{"user" => %{"username" => "an", "password" => "..."}})
assert redirected_to(conn) == "/"
assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Tài khoản đã bị khóa"

# PubSub / GenServer
Phoenix.PubSub.subscribe(TienLen.PubSub, "room:" <> id)
assert_receive {:room_chat, ^id, %{text: "chào"}}, 1_000
state = :sys.get_state(RoomServer.whereis(id))

# Doctest: ví dụ trong @doc cũng là test
#   iex> TienLen.Combination.classify(TienLen.Card.parse_many!("5H 3S 4C"))
```

- **SQL Sandbox:** mỗi test chạy trong một transaction riêng rồi rollback, nên các test chạy song song (`async: true`) không đụng dữ liệu của nhau.
- Test dùng tiến trình toàn cục (chat sảnh, presence) thì để `async: false`.
- `render_hook` gửi thẳng một event như client độc hại. Test kiểu này chứng minh server luôn kiểm tra quyền, không tin vào giao diện.

---

## 10. Thử web và API bằng curl

`curl` gửi request HTTP từ terminal, giúp thấy web thật sự trao đổi những gì.

### 10.1 Mã trạng thái và header

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4020/                 # 200
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://localhost:4020/phong/abc
# 302 http://localhost:4020/?next=%2Fphong%2Fabc
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' http://localhost:4020/images/cards/AS.svg
# 200 image/svg+xml
curl -sI http://localhost:4020/                                                  # chỉ xem header
```

- `-s`: im lặng. `-o /dev/null`: bỏ nội dung. `-w`: chỉ in những gì mình muốn.
- `-I`: chỉ lấy header. `--max-time 3`: tối đa 3 giây.

| Mã | Nghĩa | Gặp trong project |
|---|---|---|
| 200 | OK | trang sảnh |
| 302 | Chuyển hướng | vào trang cần đăng nhập khi chưa đăng nhập |
| 403 | Bị từ chối | POST thiếu CSRF token; WebSocket từ trang lạ |
| 404 | Không tìm thấy | URL sai |
| 500 | Lỗi server | xem log |

### 10.2 Đăng nhập bằng curl: cookie và CSRF token

Trình duyệt tự làm các bước này. Tự làm bằng tay sẽ hiểu cơ chế phiên đăng nhập:

```bash
B=http://localhost:4020; J=$S/cookies.txt; rm -f $J

# Hàm lấy CSRF token từ một file HTML
tok() { grep -o '<input[^>]*name="_csrf_token"[^>]*>' "$1" | head -1 | grep -o 'value="[^"]*"' | sed 's/value="//;s/"$//'; }

# 1) Lấy trang có form. Server đặt cookie phiên (-c lưu cookie) và nhúng token vào HTML
curl -s -c $J -b $J $B/ -o $S/page.html
T=$(tok $S/page.html); echo "độ dài token: ${#T}"

# 2) Gửi form đăng nhập kèm token và cookie (--data-urlencode tự mã hóa ký tự đặc biệt)
curl -s -c $J -b $J -X POST $B/dang-nhap \
  --data-urlencode "_csrf_token=$T" \
  --data-urlencode "user[username]=ten_tai_khoan" \
  --data-urlencode "user[password]=mat_khau" \
  -o /dev/null -w '%{http_code} %{redirect_url}\n'
# 302 http://localhost:4020/

# 3) Dùng lại cookie để vào trang cần đăng nhập, rồi tìm chữ trong HTML
curl -s -b $J $B/ | grep -oE 'Chat sảnh|Đang online|Tài khoản đã bị khóa' | sort -u

# 4) Thiếu token → 403 (chống giả mạo request, CSRF)
curl -s -o /dev/null -w '%{http_code}\n' -X POST $B/dang-nhap -d "user[username]=a&user[password]=b"
```

- **Cookie phiên** chứng minh "tôi đã đăng nhập". **CSRF token** chứng minh form được gửi từ chính trang của mình.
- `-c file` lưu cookie server gửi về; `-b file` gửi cookie đã lưu lên.
- **Dùng lại cookie cũ sau khi khởi động lại server** để kiểm tra phiên vẫn còn: `curl -s -b $J $B/bang-xep-hang -w '%{http_code}'`.
- Thử đăng nhập sai 5 lần rồi đăng nhập đúng: lần thứ 6 phải bị từ chối. Đây là cách kiểm tra việc chặn dò mật khẩu.

### 10.3 Kiểm tra bảo mật WebSocket (LiveView)

LiveView chạy qua WebSocket. Server chỉ nên nhận kết nối WebSocket từ chính trang của mình (kiểm tra header `Origin`):

```bash
WS='-s -o /dev/null -w %{http_code} --max-time 3 -H Connection:Upgrade -H Upgrade:websocket
    -H Sec-WebSocket-Version:13 -H Sec-WebSocket-Key:x3JJHMbDL1EzLkh9GBhXDw=='
curl $WS -H 'Origin: http://localhost:4020'   "$B/live/websocket?vsn=2.0.0"; echo   # 101 (Switching Protocols = cho phép)
curl $WS -H 'Origin: http://evil.example'     "$B/live/websocket?vsn=2.0.0"; echo   # 403 (trang lạ bị chặn)
```

### 10.4 Trích dữ liệu từ HTML

```bash
curl -s -b $J $B/bang-xep-hang -o $S/lb.html
sed -n '/id="leaderboard"/,/<\/table>/p' $S/lb.html | sed 's/<[^>]*>/ /g' | tr -s ' \n' ' '
#   sed -n '/A/,/B/p' : in đoạn từ dòng khớp A tới dòng khớp B
#   sed 's/<[^>]*>/ /g': xóa thẻ HTML;  tr -s: gộp khoảng trắng liên tiếp
grep -o '<title[^<]*' $S/page.html
grep -c 'id="logout"' $S/page.html                 # đếm: 1 = đang đăng nhập
```

`curl` chỉ thấy HTML lần render đầu, không bấm nút LiveView được. Muốn bấm nút thì dùng test LiveView (mục 9.5) hoặc trình duyệt.

### 10.5 Với API trả JSON (tham khảo chung)

```bash
curl -s http://localhost:4000/api/items | jq .
curl -s -X POST http://localhost:4000/api/items \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer <token>' \
  -d '{"name": "abc"}'
```

Project này không có JSON API (toàn bộ là LiveView), nhưng đây là dạng bạn sẽ gặp nhiều nhất khi làm web API.

---

### 10.6 Kiểm tra giao diện điện thoại bằng trình duyệt headless

Playwright điều khiển một Chromium không có cửa sổ. Nhờ đó có thể mở trang ở độ rộng 360px, đo xem trang có bị cuộn ngang không, và chụp ảnh. Công cụ có sẵn ở `tools/mobile-audit` (xem README trong đó).

```bash
cd tools/mobile-audit && npm install && npx playwright install chromium
BASE=http://localhost:4010 OUT=/tmp/shots node audit.js sau-khi-sua      # "83/83 OK" = không trang nào tràn

# Đo nhanh một trang
node -e '
const { chromium } = require("playwright");
(async () => { const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 360, height: 780 } });
  await p.goto("http://localhost:4010/");
  console.log(await p.evaluate(() => [document.documentElement.scrollWidth, innerWidth]));  // [360, 360] = không tràn
  await p.screenshot({ path: "/tmp/sanh-360.png", fullPage: true });
  await b.close(); })();'

# Chromium báo thiếu thư viện (libnspr4.so…) mà không có sudo: tải gói .deb rồi giải nén, không cài
cd /tmp/libs && apt-get download libnspr4 libnss3 libasound2t64 && for f in *.deb; do dpkg-deb -x $f root; done
export LD_LIBRARY_PATH=/tmp/libs/root/usr/lib/x86_64-linux-gnu
ldd ~/.cache/ms-playwright/*/chrome-headless-shell-linux64/chrome-headless-shell | grep "not found"   # còn thiếu gì
```

Mẹo tìm phần tử gây tràn: duyệt mọi phần tử, lấy những phần tử có `getBoundingClientRect().right` lớn hơn `innerWidth` (cách `audit.js` làm).

## 11. Docker và môi trường production

### 11.1 Vận hành hằng ngày

```bash
cd deploy
docker compose up -d --build                        # build image mới và chạy lại (migration tự chạy khi khởi động)
docker compose ps                                   # trạng thái
docker compose ps --format '{{.Name}} {{.Status}} {{.Ports}}'
docker compose logs -f tien-len                     # xem log trực tiếp (Ctrl+C để thoát)
docker compose logs --tail 200 tien-len             # 200 dòng cuối
docker compose logs tien-len 2>&1 | grep -iE "error|migrat" | tail -5
docker compose logs tien-len 2>&1 | grep -c "\[error\]"          # đếm số dòng lỗi
docker compose logs tien-len 2>&1 | grep -vE "GET|Sent" | head   # bỏ log request cho dễ đọc
docker compose restart tien-len                     # khởi động lại app (database giữ nguyên)
docker compose down                                 # dừng. ⚠ KHÔNG thêm -v: -v xóa luôn dữ liệu
```

### 11.2 Chạy code Elixir trong app production đang chạy

```bash
docker exec tien-len bin/tien_len rpc 'IO.inspect(TienLen.Lobby.list_rooms())'
docker exec tien-len bin/tien_len rpc 'IO.puts(TienLenWeb.Endpoint.url())'                 # URL app tự nhận
docker exec tien-len bin/tien_len rpc 'IO.inspect(Application.get_env(:tien_len, :max_rooms))'   # config thật

# Nhiều dòng
docker exec tien-len bin/tien_len rpc '
import Ecto.Query
n = TienLen.Repo.aggregate(TienLen.Accounts.User, :count)
IO.puts("số tài khoản: #{n}")'

docker exec -it tien-len bin/tien_len remote       # mở IEx nối vào app đang chạy (cẩn thận!)
```

- `rpc` không tự in giá trị trả về, nên phải dùng `IO.inspect` hoặc `IO.puts`.
- Mẹo **smoke test** dùng suốt project: tạo tài khoản tạm qua `rpc`, chơi thử một ván với bài chia cố định, kiểm tra coin và bảng xếp hạng, **rồi xóa tài khoản tạm**. Không đụng tới tài khoản thật.

### 11.3 Soi container và image

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep tien-len
docker inspect tien-len --format 'restart={{.HostConfig.RestartPolicy.Name}} image={{.Config.Image}}'
docker port tien-len-db                  # cổng nào được mở ra ngoài (database không nên mở)
docker volume ls | grep tien-len         # volume chứa dữ liệu database
docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "elixir|postgres"

# Chạy một container dùng một lần (--rm) từ image để soi bên trong.
# Ví dụ: kiểm tra image KHÔNG chứa file .env bí mật
docker run --rm --entrypoint sh tien-len:latest -c 'find / -name ".env*" -not -path "/proc/*" 2>/dev/null; ls /app'

docker system df                         # Docker chiếm bao nhiêu dung lượng
docker image prune                       # xóa image cũ không dùng
```

### 11.4 Sao lưu, khôi phục, và thử độ bền dữ liệu

```bash
docker compose exec -T db pg_dump -U tien_len -d tien_len --clean --if-exists > backup_$(date +%F).sql
wc -l backup_*.sql                                       # file sao lưu có nội dung không
docker compose exec -T db psql -U tien_len -d tien_len < backup_2026-09-28.sql   # khôi phục

# Dữ liệu có sống sót qua restart và down/up không?
docker compose restart; docker compose down; docker compose up -d
# … rồi dùng lại cookie cũ (mục 10.2) để kiểm tra vẫn đăng nhập được và bảng xếp hạng còn nguyên
```

---

## 12. Tìm kiếm, đọc và sửa file nhanh

```bash
grep -rn "def join" lib/                      # tìm trong cả thư mục, kèm số dòng
grep -n "  def \|@doc" lib/tien_len/game.ex   # danh sách hàm của một file
grep -rn "Presence.move" lib test             # hàm này được gọi ở đâu?
grep -c "test \"" test/tien_len/bot_test.exs  # đếm số test trong file
grep -rn "secret_key_base" config/            # cấu hình này đặt ở đâu
grep -o 'RULES §[0-9.]*' -h CLAUDE.md docs/*.md | sort | uniq -c   # đếm số lần mỗi mục được nhắc tới

sed -n 40,80p lib/tien_len/room.ex            # in dòng 40–80
sed -n '/### Project decisions/,/## Phase 1 results/p' docs/PORTING_STATUS.md   # in một đoạn giữa hai tiêu đề
sed -n "$(grep -n 'def view' lib/tien_len/game.ex | cut -d: -f1),+30p" lib/tien_len/game.ex
                                              # in 30 dòng từ chỗ khai báo hàm
cat -n file                                   # in kèm số dòng
wc -l lib/tien_len/*.ex                       # số dòng mỗi file
ls priv/repo/migrations                       # các migration đã có
tail -f /đường/dẫn/log                        # theo dõi file log

# Sửa nhanh bằng sed (cẩn thận: sửa thẳng vào file!)
sed -i 's/chữ cũ/chữ mới/' file               # thay lần đầu mỗi dòng
sed -i '/dòng cần xóa/d' file                 # xóa dòng khớp mẫu
git diff file                                 # LUÔN xem lại sau khi sửa bằng sed
```

Công cụ của Elixir:

```bash
mix xref callers TienLen.Economy              # những file nào gọi module này?
mix xref graph --format stats                 # thống kê phụ thuộc giữa các module
```

---

## 13. Git

```bash
git init -b main                   # tạo repo mới với nhánh main
git config user.name; git config user.email      # commit sẽ mang tên ai

git status --short                 # file nào đổi (M = sửa, ?? = mới)
git status --short --ignored deploy               # thấy cả file bị .gitignore bỏ qua
git diff                           # chi tiết thay đổi chưa stage
git diff --stat                    # tóm tắt: file nào, bao nhiêu dòng
git add -A                         # stage tất cả
git diff --cached --name-only      # danh sách file SẮP được commit
git diff --cached --stat | tail -1 # tổng: bao nhiêu file, bao nhiêu dòng

# Chặn lỡ tay commit file bí mật (không in gì = an toàn)
git diff --cached --name-only | grep -E "(^|/)\.env$" && echo "DỪNG: .env đang được stage"
git check-ignore deploy/.env       # in ra tên file = file đã được .gitignore bỏ qua

# Commit nhiều dòng bằng heredoc
git commit -F - <<'EOF'
Tiêu đề ngắn gọn

- chi tiết 1
- chi tiết 2
EOF

git log --oneline -5               # 5 commit gần nhất
git log -1 --format=%h -- docs/ARCHITECTURE.md    # lần cuối file này được sửa (tìm tài liệu bị cũ)
git show --stat HEAD               # commit cuối gồm những file nào
```

Các lệnh đào lịch sử (`git log -S`, `git show <commit>^:file`…) ở mục 3.2.

---

## 14. Quy trình mẫu

**Nghiên cứu một repo lạ:**
1. `git log`, `find`, `cat package.json` / `mix.exs`: nắm cấu trúc.
2. Đọc code chính bằng `for f in …; do cat -n $f; done`.
3. `rsync` ra bản sao, cài thư viện, chạy test gốc.
4. Viết test thăm dò để kiểm chứng giả thuyết.
5. Ghi kết quả, đánh dấu cái nào **VERIFIED** (đã chạy thử) và cái nào chưa.

**Thêm một tính năng có database:**

```bash
mix ecto.gen.migration add_something      # 1. viết migration
mix ecto.migrate && MIX_ENV=test mix ecto.migrate
#                                         # 2. sửa schema, context, LiveView, viết test
mix test test/đường/dẫn/test_mới.exs      # 3. chạy test mới
mix precommit                             # 4. toàn bộ: compile, format, test
for i in $(seq 1 5); do mix test 2>&1 | grep -E "^Result|\) test"; done
#                                         # 5. chạy lặp để bắt test flaky
cd deploy && docker compose up -d --build # 6. deploy
docker compose logs tien-len 2>&1 | grep -iE "migrat|error" | tail   # 7. migration có chạy không, có lỗi không
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4020/      # 8. smoke test
```

**Khi test fail:**
1. `mix test 2>&1 | grep -E "\) test|left:|right:"`: test nào fail, giá trị sai là gì.
2. `mix test file:dòng --trace`: chạy riêng test đó.
3. Chỉ thỉnh thoảng fail? Chạy lại với seed đó (`--seed`), hoặc dùng các vòng lặp ở mục 9.3.
4. Sửa xong: `mix test --failed`, rồi `mix precommit`.

**Khi production có vấn đề:**
1. `docker compose ps`: container có đang chạy không?
2. `docker compose logs --tail 200 tien-len`: đọc lỗi gần nhất.
3. `docker exec tien-len bin/tien_len rpc '...'`: soi dữ liệu hoặc tiến trình bên trong app.
4. `docker exec tien-len-db psql ... -tc "select ..."`: soi dữ liệu trực tiếp trong database.
