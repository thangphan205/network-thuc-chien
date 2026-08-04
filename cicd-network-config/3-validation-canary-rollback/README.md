# Lab 3 — Validation & Canary/Rollback

Minh hoạ **Mô hình 3: Validation-first / Digital-twin pipeline** ([xem lý thuyết](../README.md#5-mô-hình-3-validation-first--digital-twin-pipeline)) — không đẩy config thẳng lên tất cả thiết bị, mà đi qua nhiều tầng kiểm định + canary + rollback tự động.

```
3-validation-canary-rollback/
├── topology.clab.yml            # 3 node: canary1 (canary group) + node2, node3 (rest group)
├── batfish_check.py             # Stage "unit test cấu hình"
├── configs/                     # Config export dùng cho Batfish (placeholder)
└── ansible/
    ├── inventory.yml            # group "canary" (canary1) và "rest" (node2, node3)
    └── rollout_with_rollback.yml # Stage canary + health-check + auto-rollback
```

Workflow CI tương ứng: [`.github/workflows/network-cicd-3-validation.yml`](../../.github/workflows/network-cicd-3-validation.yml).

## Pipeline 5 stage

| Stage | File | Mô tả |
| :--- | :--- | :--- |
| 1. Lint | job `lint` trong workflow | `yamllint` + `ansible-lint` |
| 2. Unit test (Batfish) | `batfish_check.py` | Phát hiện lỗi tham chiếu trước khi đụng thiết bị thật |
| 3. Digital-twin apply | `topology.clab.yml` | Containerlab đóng luôn vai trò digital-twin — không có prod thật ở lab này |
| 4. Canary + health-check | `ansible/rollout_with_rollback.yml` | `serial: 1`, canary1 chạy trước, health-check bằng `assert` |
| 5. Rollback | block `rescue` trong cùng playbook | Restore config từ backup nếu health-check fail |

## Chạy local

1. Dựng topology:

   ```bash
   sudo containerlab deploy -t topology.clab.yml
   ```

2. (Tuỳ chọn) Batfish pre-check — cần Docker:

   ```bash
   docker run -d --name batfish -p 9997:9997 -p 9996:9996 batfish/allinone
   pip install pybatfish
   docker exec clab-cicd_validation_lab-canary1 vtysh -c "show running-config" > configs/canary1.cfg
   docker exec clab-cicd_validation_lab-node2 vtysh -c "show running-config" > configs/node2.cfg
   docker exec clab-cicd_validation_lab-node3 vtysh -c "show running-config" > configs/node3.cfg
   python batfish_check.py
   ```

3. Set credentials và chạy rollout:

   ```bash
   export LAB_DEVICE_PASSWORD=<mật khẩu lab>
   export LAB_ENABLE_PASSWORD=<enable password lab>
   cd ansible
   ansible-galaxy collection install cisco.ios
   ansible-playbook -i inventory.yml rollout_with_rollback.yml
   ```

   `canary1` chạy trước; chỉ khi health-check trên `canary1` PASS thì `node2`, `node3` mới được đụng tới (`any_errors_fatal: true`).

## Thử kịch bản rollback

Sửa dòng `assert` trong `rollout_with_rollback.yml` thành một điều kiện chắc chắn sai (ví dụ `that: "'8.8.8.8' in health_check.stdout[0]"`), chạy lại playbook — bạn sẽ thấy:

1. `canary1` apply config mới.
2. Health-check fail.
3. Block `rescue` restore config từ `./backup/canary1.cfg`.
4. Playbook dừng hẳn — `node2`, `node3` không hề bị chạm tới.

## Dọn lab

```bash
sudo containerlab destroy -t topology.clab.yml
docker rm -f batfish
```
