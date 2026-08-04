# Lab 2 — GitOps Pull

Minh hoạ **Mô hình 2: GitOps Pull** ([xem lý thuyết](../README.md#4-mô-hình-2-gitops-pull)) — một poller chạy trên jump-host tự kéo Git về và áp dụng config idempotent, thay vì CI SSH thẳng vào thiết bị như Mô hình 1.

```
2-gitops-pull-poller/
├── topology.clab.yml       # 2 node cisco_iol
└── poller/
    ├── desired_state.yml   # "config as code" - trạng thái mong muốn của từng device
    ├── poller.py            # vòng lặp: (git pull) -> diff -> apply idempotent qua NAPALM
    └── requirements.txt
```

## Git repo riêng cho state

Trong triển khai thật, `desired_state.yml` nằm ở **một Git repo tách biệt** khỏi repo chứa code poller — jump-host chỉ cần quyền `git pull` (đọc, qua HTTPS) từ repo đó, **không cần** ai từ CI/SaaS mở kết nối SSH vào thiết bị. Trong lab này để đơn giản, file nằm sẵn trong repo — bật `GIT_CONFIG_REPO_PATH` nếu bạn muốn poller tự `git pull` một repo ngoài trước mỗi vòng.

## Chạy local

1. Dựng topology:

   ```bash
   sudo containerlab deploy -t topology.clab.yml
   ```

2. Cài dependency:

   ```bash
   cd poller
   pip install -r requirements.txt
   ```

3. Set credentials:

   ```bash
   export LAB_DEVICE_USERNAME=backup_user
   export LAB_DEVICE_PASSWORD=<mật khẩu lab>
   export LAB_ENABLE_PASSWORD=<enable password lab>
   ```

4. Chạy 1 vòng (giống CI schedule job gọi vào) để thấy poller phát hiện & áp DNS server còn thiếu:

   ```bash
   python poller.py --once
   ```

5. Chạy lại lần 2 — lần này phải in ra **"khong lech - bo qua (idempotent)"** cho cả 2 thiết bị, vì config đã khớp desired state.

6. (Tuỳ chọn) chạy như daemon thật, poll mỗi 60s:

   ```bash
   python poller.py --interval 60
   ```

## So sánh nhanh với Lab 1 (Push)

| | Lab 1 — Push | Lab 2 — Pull |
| :--- | :--- | :--- |
| Ai chủ động SSH vào thiết bị | GitHub Actions runner | `poller.py` chạy nội bộ |
| Trigger | Merge PR | Chu kỳ thời gian (`--interval`) |
| Thử idempotent | Chạy `push_config.yml` 2 lần — vẫn apply lại (ansible tự idempotent) | Chạy `poller.py --once` 2 lần — lần 2 log rõ "bỏ qua" nhờ `compare_config()` rỗng |

## Dọn lab

```bash
sudo containerlab destroy -t topology.clab.yml
```
