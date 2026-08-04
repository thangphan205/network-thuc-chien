# Lab 4 — Golden-config / Drift-detection

Minh hoạ **Mô hình 4: Golden-config / Drift-detection** ([xem lý thuyết](../README.md#6-mô-hình-4-golden-config--drift-detection)) — không triển khai thay đổi mới, mà liên tục so sánh running-config thực tế với intended config để phát hiện lệch.

```
4-golden-config-drift-detection/
├── topology.clab.yml
└── ansible/
    ├── inventory.yml              # dns_servers "intended" khai báo per-host
    ├── templates/dns_intended.j2  # sinh intended config từ template
    └── golden_config_check.yml    # render -> lấy running -> diff -> report (+ remediate tuỳ chọn)
```

Workflow CI tương ứng (chạy theo lịch, không theo push/PR): [`.github/workflows/network-cicd-4-golden-config.yml`](../../.github/workflows/network-cicd-4-golden-config.yml).

## Chạy local

1. Dựng topology:

   ```bash
   sudo containerlab deploy -t topology.clab.yml
   ```

2. Set credentials:

   ```bash
   export LAB_DEVICE_PASSWORD=<mật khẩu lab>
   export LAB_ENABLE_PASSWORD=<enable password lab>
   ```

3. Chạy drift check (thiết bị mới deploy chưa có DNS server → sẽ báo drift và **fail** có chủ đích):

   ```bash
   cd ansible
   ansible-galaxy collection install cisco.ios
   ansible-playbook -i inventory.yml golden_config_check.yml
   ```

4. Tự động remediate drift vừa phát hiện:

   ```bash
   ansible-playbook -i inventory.yml golden_config_check.yml -e remediate=true
   ```

5. Chạy lại không kèm `remediate=true` — lần này phải thấy **"Compliant"** cho cả 2 host, playbook không fail.

6. Thử tạo drift thủ công (mô phỏng ai đó SSH tay sửa config ngoài luồng CI):

   ```bash
   docker exec -it clab-cicd_golden_config_lab-cisco1 vtysh -c "configure terminal" -c "no ip name-server 192.168.1.10"
   ansible-playbook -i inventory.yml golden_config_check.yml
   ```

   Playbook sẽ phát hiện lại drift dù không có commit/PR nào xảy ra — đúng vai trò "lưới an toàn" bổ trợ cho Mô hình 1-3.

## Dọn lab

```bash
sudo containerlab destroy -t topology.clab.yml
```
