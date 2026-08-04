# Lab 1 — GitOps Push

Minh hoạ **Mô hình 1: GitOps Push** ([xem lý thuyết](../README.md#3-mô-hình-1-gitops-push)) — CI chủ động đẩy config xuống thiết bị ngay khi PR merge vào `main`.

```
1-gitops-push-ansible-github-actions/
├── topology.clab.yml          # 2 node cisco_iol, dùng chung startup-config lab của network-automation
└── ansible/
    ├── inventory.yml          # định nghĩa 2 device, creds lấy từ biến môi trường
    └── playbooks/             # mỗi loại thay đổi 1 template riêng
        ├── push_dns.yml       # DNS name-server -> intended state
        ├── push_acl.yml       # ACL/firewall rule -> intended state
        └── push_bgp.yml       # BGP neighbor + route-map policy -> intended state
```

**Vì sao tách theo template thay vì 1 file chung**: netadmin quen CLI Cisco/Juniper không cần học hết schema YAML cùng lúc — đổi DNS chỉ đụng `push_dns.yml`, đổi ACL chỉ đụng `push_acl.yml`. Mỗi file map gần 1:1 với 1 nhóm lệnh CLI quen thuộc (`ip name-server`, `access-list`, `router bgp` + `neighbor ... route-map`), chỉ khác là khai báo dưới dạng YAML để CI lint/diff được trước khi chạm thiết bị. CI luôn chạy cả 3 playbook mỗi lần merge — playbook không có gì thay đổi thì idempotent, không tạo thay đổi trên thiết bị (no-op).

Workflow CI tương ứng: [`.github/workflows/network-cicd-1-push.yml`](../../.github/workflows/network-cicd-1-push.yml).

## Triển khai thật lên server (product-ready)

Phần dưới đây là lab demo chạy trên containerlab. Để triển khai **thật** lên thiết bị production — server Linux (Ubuntu 24.04) chạy Ansible qua Docker Compose, không qua containerlab — xem runbook [`product-ready/README.md`](./product-ready/README.md).

## Chạy local

1. Dựng topology:

   ```bash
   sudo containerlab deploy -t topology.clab.yml
   ```

2. Set credentials (trùng với user `backup_user` trong `network-automation/containerlab/config/cisco.config.partial`):

   ```bash
   export LAB_DEVICE_PASSWORD=<mật khẩu lab>
   export LAB_ENABLE_PASSWORD=<enable password lab>
   ```

3. Cài collection cần thiết:

   ```bash
   ansible-galaxy collection install cisco.ios
   ```

4. Dry-run trước để chắc chắn không lỗi cú pháp (thay `push_dns.yml` bằng file template tương ứng loại thay đổi bạn cần):

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbooks/push_dns.yml --check --diff
   ansible-playbook -i inventory.yml playbooks/push_acl.yml --check --diff
   ansible-playbook -i inventory.yml playbooks/push_bgp.yml --check --diff
   ```

5. Apply thật — đây chính là bước mà CI sẽ tự chạy khi PR merge vào `main`:

   ```bash
   ansible-playbook -i inventory.yml playbooks/push_dns.yml playbooks/push_acl.yml playbooks/push_bgp.yml
   ```

6. Verify trên thiết bị:

   ```bash
   docker exec -it clab-cicd_push_lab-cisco1 vtysh -c "show running-config | include name-server"
   docker exec -it clab-cicd_push_lab-cisco1 vtysh -c "show access-lists 101"
   docker exec -it clab-cicd_push_lab-cisco1 vtysh -c "show ip bgp summary"
   ```

## Cách CI vận hành

- Mở PR sửa 1 trong 3 template (`playbooks/push_dns.yml`, `push_acl.yml`, hoặc `push_bgp.yml`) → job `lint` chạy `yamllint` + `ansible-lint`, không chạm thiết bị.
- Merge vào `main` → job `push` (chạy trên self-hosted runner có network reach tới lab) apply cả 3 playbook thật — playbook nào không đổi thì idempotent, no-op trên thiết bị.
- Đây là điểm khác biệt cốt lõi với Mô hình 2 (Pull): **CI chủ động kết nối tới thiết bị**, chứ thiết bị không tự đi lấy config.

## Giới hạn của template ACL/BGP ở đây

Lab này minh hoạ mô hình push cơ bản — **không có validation/canary** như Mô hình 3. Với ACL/BGP, config sai apply thẳng có thể chặn nhầm traffic hoặc gây route leak ngay khi merge. Muốn an toàn hơn cho 2 loại config này, xem [`../3-validation-canary-rollback/`](../3-validation-canary-rollback/) — có Batfish pre-check + canary + auto-rollback trước khi áp dụng toàn bộ.

## Dọn lab

```bash
sudo containerlab destroy -t topology.clab.yml
```
