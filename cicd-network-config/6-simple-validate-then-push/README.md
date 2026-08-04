# Lab 6 — Simple Validate-then-Push

Netadmin mở PR sửa file cấu hình → GitHub Actions chạy Batfish kiểm tra thay đổi → **Batfish PASS thì CI tự động push xuống thiết bị thật, không cần ai bấm approve.** Không canary, không rollback, không cổng chờ người duyệt — chỉ có 1 điều kiện duy nhất để push: Batfish không phát hiện lỗi.

> **Tự chứa hoàn toàn**: chỉ cần `cd` vào thư mục này là chạy được — không cần file nào ở ngoài. `config/cisco.config.partial`, `docker-compose.yml`, `requirements.txt` đều đã có sẵn trong đây.

---

## Luồng vận hành

```mermaid
sequenceDiagram
    participant Net as Netadmin
    participant Git as Pull Request
    participant CI as GitHub Actions
    participant BF as Batfish
    participant Dev1 as Router (production)

    Net->>Git: Mở PR, sửa configs/proposed/configs/*.cfg
    Git->>CI: Trigger workflow (pull_request)
    CI->>CI: Lint (yamllint + ansible-lint)
    CI->>BF: init_snapshot base + proposed
    BF-->>CI: filterLineReachability + differentialReachability + bgpSessionStatus
    CI->>Git: Post gate_report.md làm PR comment
    alt Batfish FAIL
        CI-->>Net: Pipeline đỏ, chặn merge — sửa lại config
    else Batfish PASS
        Net->>Git: Merge PR vào main
        Git->>CI: Trigger workflow lần nữa (push to main)
        CI->>BF: Chạy lại Batfish gate (không tin tưởng mù quáng vào lần chạy PR)
        BF-->>CI: PASS
        CI->>Dev1: Ansible ios_config push config that
        Dev1-->>CI: Kết quả apply
        CI-->>Net: Báo thành công — KHÔNG có bước người duyệt
    end
```

Job Batfish gate **chạy lại trên chính sự kiện `push` vào `main`**, không chỉ trên `pull_request` — pipeline tự enforce "phải kiểm tra trước khi push" ngay trong cùng 1 workflow run, không phụ thuộc hoàn toàn vào cấu hình branch-protection của GitHub (dù vẫn nên bật thêm để chặn merge trực tiếp không qua CI).

Workflow CI tương ứng: [`.github/workflows/network-cicd-6-simple-validate-push.yml`](../../.github/workflows/network-cicd-6-simple-validate-push.yml).

---

## Cấu trúc

```text
6-simple-validate-then-push/
├── README.md
├── topology.clab.yml         # cisco1 (cisco_iol) + juniper1 (juniper_crpd), có link cisco1:eth1 <-> juniper1:eth1
├── docker-compose.yml        # Batfish server (batfish/allinone) — chạy local, tự chứa
├── requirements.txt          # pybatfish, pandas, tabulate, rich
├── config/
│   └── cisco.config.partial  # startup-config dùng chung cho node cisco_iol
├── configs/
│   ├── base/configs/         # config production hiện tại (golden) — KHÔNG sửa trong PR
│   └── proposed/configs/     # config đề xuất — netadmin sửa file ở đây khi mở PR
├── batfish_gate.py           # Script Batfish gate — 3 kiểm tra, không có bước approve
└── ansible/
    ├── inventory.yml         # host cisco1, host var config_name quyết định file .cfg nào được push
    ├── requirements.yml      # collection cisco.ios
    └── push_config.yml       # push raw config từ configs/proposed/configs/ xuống thiết bị
```

**Vì sao `configs/base/configs/` và `configs/proposed/configs/` có 2 cấp `configs` lồng nhau**: đây không phải lỗi đánh máy — Batfish **bắt buộc** thư mục truyền vào `init_snapshot()` phải chứa 1 subfolder tên đúng là `configs/` (hoặc `hosts/`/`aws_configs/`/`sonic_configs/`) bên trong mới nhận là snapshot hợp lệ; truyền thẳng thư mục chứa file `.cfg` sẽ bị Batfish server trả lỗi 400 "Unexpected packaging of snapshot". `batfish_gate.py` gọi `init_snapshot("configs/base", ...)` — tức `configs/base` là snapshot root, và file `.cfg` thật nằm ở `configs/base/configs/*.cfg`.

`configs/base` chứa 4 thiết bị (`fw-edge`, `r1-core`, `r2-core`, `sw-dist1`) — Batfish validate toàn bộ 4 thiết bị này mỗi lần chạy gate, kể cả khi topology chỉ deploy 1 node thật (`cisco1`, đóng vai `fw-edge` qua host var `config_name` trong `ansible/inventory.yml`). Đây là chủ đích: Batfish là bước "kiểm tra thay đổi trên giấy" cho toàn bộ CR, còn `push` chỉ target đúng những thiết bị thật khai báo trong `ansible/inventory.yml`.

2 lỗi có sẵn trong `configs/proposed/configs/` để demo FAIL:

1. **ACL shadowed rule** trên `fw-edge`: dòng `permit tcp 10.10.10.0 ...` bị che khuất bởi dòng `deny ip any 10.20.20.0/24` đứng trước.
2. **BGP neighbor IP typo** trên `r2-core`: `neighbor 1.1.1.99` (đúng phải là `1.1.1.1`) → session BGP giữa `r1-core` và `r2-core` không lên được (cả 2 phía đều báo `NOT_COMPATIBLE`).

> **Lưu ý đã verify thật**: check "Differential Reachability (App→DB)" trong `batfish_gate.py` **không** bắt được lỗi ACL này, dù ACL bug vẫn được check 1 (`filterLineReachability`) phát hiện đúng. Lý do: ACL `SEC-ACL-IN` áp trên interface WAN-facing của `fw-edge`, còn traffic App(VLAN10)→DB(VLAN20) đi nội bộ qua `sw-dist1`/`r1-core`, không đi qua `fw-edge` — nên bug ACL này không ảnh hưởng route đó. Gate vẫn FAIL đúng (nhờ check ACL), chỉ riêng check reachability không phải là bằng chứng cho bug này.

---

## Chạy thử local

Interface thật trên `cisco_iol` là `Ethernet0/0`–`Ethernet0/3` (đã xác nhận qua boot log thật), nên các file `.cfg` trong lab này dùng `Ethernet0/x`, không phải `GigabitEthernet0/x`.

### 1. Batfish gate — demo FAIL

```bash
pip install -r requirements.txt
docker compose up -d
python batfish_gate.py
```

Kỳ vọng: `exit 1`. `gate_report.md` liệt kê: ACL shadow trên `fw-edge`, và BGP session `NOT_COMPATIBLE` trên `r1-core`/`r2-core`.

### 2. Sửa config — demo PASS

Sửa `configs/proposed/configs/fw-edge.cfg`: bỏ dòng `deny ip any 10.20.20.0 0.0.0.255` và remark lỗi phía trên nó (khôi phục giống `configs/base/configs/fw-edge.cfg`).

Sửa `configs/proposed/configs/r2-core.cfg`: đổi `neighbor 1.1.1.99` → `neighbor 1.1.1.1` ở cả 2 dòng (khôi phục giống `configs/base/configs/r2-core.cfg`).

```bash
python batfish_gate.py
```

Kỳ vọng: `exit 0`, PASS. (Đã verify thật trên Batfish server — cả FAIL và PASS đều ra đúng kết quả.)

### 3. Deploy digital-twin và push thật

```bash
sudo containerlab deploy -t topology.clab.yml
docker exec -it clab-cicd_simple_validate_push_lab-cisco1 vtysh -c "show ip interface brief"   # kiểm tra interface trước khi push

export LAB_DEVICE_PASSWORD=<mật khẩu lab>
export LAB_ENABLE_PASSWORD=<enable password lab>

ansible-galaxy collection install -r ansible/requirements.yml

cd ansible
ansible-playbook -i inventory.yml push_config.yml --check --diff   # dry-run trước
ansible-playbook -i inventory.yml push_config.yml                  # apply thật
```

### 4. Verify trên thiết bị

```bash
docker exec -it clab-cicd_simple_validate_push_lab-cisco1 vtysh -c "show ip access-lists SEC-ACL-IN"
```

> Nếu `vtysh` không hoạt động trên `cisco_iol` khi bạn deploy thật (quirk tuỳ phiên bản image), dùng `ansible -i ansible/inventory.yml all -m cisco.ios.ios_command -a "commands='show running-config'"` thay thế.

---

## Cách CI vận hành

- Mở PR sửa file trong `configs/proposed/configs/` → job `lint` (yamllint + ansible-lint), sau đó job `batfish-gate` spin Batfish server, chạy `batfish_gate.py`, post `gate_report.md` làm PR comment.
- Batfish FAIL → pipeline đỏ, PR bị chặn.
- Batfish PASS → PR có thể merge. Khi merge vào `main`, workflow trigger lại: job `batfish-gate` chạy lại (an toàn, không tin lần chạy PR trước), rồi job `push` (self-hosted runner có network reach tới lab) tự động `ansible-playbook push_config.yml` — **không có bước chờ người duyệt**.

---

## Thiết lập GitHub repo + GitHub Actions

Lab chạy được local (mục "Chạy thử local" ở trên) không cần bước này. Bước này chỉ cần khi muốn pipeline tự chạy qua PR/merge thật trên GitHub.

### 1. Tạo repo và đẩy code lên

```bash
# Nếu chưa có repo Git nào:
git init
git add .
git commit -m "init: simple validate-then-push lab"

# Tạo repo mới trên GitHub (cần gh CLI đã login), hoặc tạo tay trên github.com > New repository
gh repo create <owner>/<ten-repo> --private --source=. --remote=origin

# Nếu repo đã tồn tại, chỉ cần trỏ remote rồi push
git remote add origin git@github.com:<owner>/<ten-repo>.git
git push -u origin main
```

> Nếu `git push` báo `Permission denied (publickey)`: SSH agent chưa load key. Kiểm tra `ssh-add -l` — nếu ra `The agent has no identities`, chạy `ssh-add ~/.ssh/<ten-key-private>` rồi thử push lại. Hoặc đổi remote sang HTTPS (`git remote set-url origin https://github.com/<owner>/<ten-repo>.git`) và dùng Personal Access Token khi push.

### 2. Cài self-hosted runner trên đúng server lab

Job `push` trong workflow khai báo `runs-on: self-hosted` vì nó cần network reach trực tiếp tới mgmt subnet của containerlab (`192.168.26.0/24`) — **runner phải cài ngay trên server đang chạy containerlab** (không phải máy khác), và server đó cần sẵn `docker`, `containerlab`, `ansible`, collection `cisco.ios`.

Trên GitHub: repo → **Settings → Actions → Runners → New self-hosted runner** → chọn Linux x64, copy đúng bộ lệnh GitHub hiển thị (có token riêng, không tái sử dụng lệnh cũ), chạy trên server lab:

```bash
mkdir actions-runner && cd actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/<version>/actions-runner-linux-x64-<version>.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/<owner>/<ten-repo> --token <TOKEN_TU_GITHUB>

# Chạy nền dạng service để runner luôn online, không cần giữ SSH session:
sudo ./svc.sh install
sudo ./svc.sh start
```

Verify: repo → Settings → Actions → Runners → runner hiện trạng thái **Idle** (màu xanh).

### 3. Thêm Secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**, thêm 2 secret:

- `LAB_DEVICE_PASSWORD` — password SSH của `backup_user`.
- `LAB_ENABLE_PASSWORD` — enable password (nếu khác password SSH; nếu `backup_user` đã privilege 15 thì có thể set trùng giá trị).

### 4. (Khuyến nghị) Branch protection cho `main`

Repo → **Settings → Branches → Add branch protection rule**, branch pattern `main`:

- Tick **Require status checks to pass before merging**, chọn job `lint` và `batfish-gate`.
- (Tuỳ chọn) Tick **Require a pull request before merging**.

Không có bước này thì ai đó vẫn có thể `git push` thẳng vào `main` mà bỏ qua Batfish gate — job `batfish-gate` vẫn chạy lại trên sự kiện `push` (xem mục "Luồng vận hành" ở trên) nhưng chỉ *chặn được job `push` chạy tiếp*, không chặn được việc code sai đã nằm trên `main`. Branch protection mới thật sự ngăn được merge khi CI đỏ.

### 5. Kịch bản Demo thực hành chi tiết

Chi tiết từng bước cấu hình Runner, thử nghiệm PR gây lỗi (Batfish FAIL), sửa lỗi (Batfish PASS), và xem kết quả đẩy cấu hình tự động xuống `cisco1` được tách riêng tại file **[DEMO.md](./DEMO.md)**.

---



## Đã verify thật trên server (không chỉ đọc code)

Đã deploy thật `topology.clab.yml` trên 1 server lab (containerlab 0.77.0):

- `cisco1` (cisco_iol, IOS-XE 17.15.1) và `juniper1` (juniper_crpd) đều lên `running`, link `cisco1:eth1 ↔ juniper1:eth1` xác nhận `UP/UP` (qua `show interfaces terse` trên `juniper1`).
- Batfish gate chạy thật với server `batfish/allinone` — cả kịch bản FAIL (bug ACL + BGP gốc) và PASS (sau khi sửa) đều ra đúng kết quả, `exit 1`/`exit 0` đúng như thiết kế.
- 2 bug thật phát hiện được trong lúc test (đã sửa vào code, không phải giả định):
  1. `pybatfish` bản mới (≥2025.x) đổi tên class `Header` → `HeaderConstraints`. `batfish_gate.py` đã cập nhật theo tên mới.
  2. Batfish snapshot bắt buộc có subfolder `configs/` lồng bên trong — cấu trúc thư mục ban đầu (`configs/base/*.cfg` phẳng) bị Batfish từ chối với lỗi 400. Đã restructure thành `configs/base/configs/*.cfg`.
- Bước push thật (Ansible `ios_config` xuống `cisco1`) **chưa verify được** — cần `LAB_DEVICE_PASSWORD` thật (hash type-9 trong `config/cisco.config.partial` không đảo ngược được) mà chưa có trong lần test này. Cấu hình push (`ansible/push_config.yml`, path `configs/proposed/configs/{{ config_name }}.cfg`) đã đúng theo cấu trúc thư mục hiện tại nhưng còn 1 bước cuối cần test khi có credential.

## Triển khai với GitLab (GitLab CI/CD & GitLab Backup Option)

Ngoài GitHub Actions, bài 6 hỗ trợ sẵn 2 tùy chọn triển khai trên GitLab:

### 1. GitLab CI/CD Pipeline (`.gitlab-ci.yml`)

File `.gitlab-ci.yml` có sẵn tại thư mục gốc với 3 stage tương đương:
- `lint-job`: Chạy `yamllint` và `ansible-lint`.
- `batfish-gate-job`: Dùng `docker:dind` để spin-up Batfish server và chạy `python3 batfish_gate.py`.
- `push-to-devices-job`: Chạy Ansible playbook push cấu hình xuống thiết bị trên GitLab Self-hosted Runner (`tags: [self-hosted, server-lab]`).

### 2. Tùy chọn tự động đẩy cấu hình lên repo GitLab (`push_config.yml`)

Khi Ansible push thành công cấu hình xuống thiết bị thật, bạn có thể tự động đẩy lại bản backup/proposed config lên repo GitLab bằng cách set biến môi trường `GITLAB_REPO_URL` (ví dụ `https://oauth2:YOUR_GITLAB_TOKEN@gitlab.com/username/network-configs.git`):

```bash
export GITLAB_REPO_URL="https://oauth2:<TOKEN>@gitlab.com/<username>/<repo>.git"
ansible-playbook -i ansible/inventory.yml ansible/push_config.yml
```

---

## Dọn lab

```bash
sudo containerlab destroy -t topology.clab.yml
docker compose down
```

