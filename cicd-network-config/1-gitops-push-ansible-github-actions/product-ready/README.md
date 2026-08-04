# Product-ready — Triển khai GitOps Push lên server thật (Ubuntu 24.04)

Runbook triển khai **thật** — server Linux này đóng vai trò máy quản trị/CI runner có đường mạng SSH tới router/switch thật, chạy Ansible qua Docker Compose để đẩy config. Khác với lab demo (containerlab) ở [README gốc](../README.md): ở đây không có `topology.clab.yml`, thiết bị là hardware/VM thật.

## 1. Yêu cầu hạ tầng

- Ubuntu Server 24.04 LTS, user có quyền `sudo`.
- Server có đường mạng SSH (port 22) tới management IP của toàn bộ thiết bị trong `inventory.yml`.
- Tài khoản `backup_user` (hoặc tài khoản service account tương đương) đã được cấu hình sẵn trên thiết bị, đúng quyền `privilege 15` + `enable secret`.

## 2. Cài Docker Engine + Compose plugin

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker
```

Kiểm tra:

```bash
docker --version
docker compose version
```

## 3. Lấy source lên server

```bash
git clone <repo-url> network-thuc-chien
cd "network-thuc-chien/cicd-network-config/1-gitops-push-ansible-github-actions/product-ready"
```

## 4. Trỏ inventory về thiết bị thật

Chọn 1 trong 2 nguồn inventory, khai báo qua biến `INVENTORY` trong `.env` (bước 5):

### 4a. File tĩnh (mặc định, `INVENTORY=inventory.yml`)

Sửa [`../ansible/inventory.yml`](../ansible/inventory.yml) — thay `ansible_host` bằng IP quản trị thật của từng thiết bị (đổi tên host tùy ý, không bắt buộc giữ `cisco1`/`cisco2`):

```yaml
all:
  hosts:
    router-hn-01:
      ansible_host: 10.10.0.1
    router-hcm-01:
      ansible_host: 10.20.0.1
  vars:
    ansible_network_os: ios
    ansible_connection: network_cli
    ansible_user: backup_user
    ansible_password: "{{ lookup('env', 'LAB_DEVICE_PASSWORD') }}"
    ansible_become: yes
    ansible_become_method: enable
    ansible_become_password: "{{ lookup('env', 'LAB_ENABLE_PASSWORD') }}"
```

Phù hợp khi danh sách thiết bị cố định/ít đổi.

### 4b. NetBox dynamic inventory (`INVENTORY=netbox_inventory.yml`)

Nếu NetBox đã là nguồn chân lý (source of truth) cho danh sách thiết bị, dùng [`netbox_inventory.yml`](./netbox_inventory.yml) — Ansible tự query NetBox API thay vì đọc file tĩnh. Đã cài sẵn collection `netbox.netbox` + `pynetbox` trong image.

- Set `NETBOX_API`, `NETBOX_TOKEN` trong `.env` (bước 5) — plugin tự đọc 2 biến này.
- Chỉnh `query_filters` (status/site/role...) trong `netbox_inventory.yml` cho khớp schema NetBox thật của bạn — mặc định chỉ lọc `status: active`.
- `compose:` trong file này gán sẵn `ansible_user: backup_user` + creds từ `LAB_DEVICE_PASSWORD`/`LAB_ENABLE_PASSWORD`, giống file tĩnh — không cần lưu password trong NetBox.

Kiểm tra inventory NetBox trả về đúng chưa, trước khi apply:

```bash
docker compose run --rm --entrypoint "ansible-inventory -i netbox_inventory.yml --list" push
```

Và sửa `dns_servers` (hoặc state mong muốn khác) trong [`../ansible/push_config.yml`](../ansible/push_config.yml) theo đúng intent thật, không phải giá trị demo lab.

## 5. Khai báo credential

```bash
cp .env.example .env
chmod 600 .env
```

Điền `LAB_DEVICE_PASSWORD`, `LAB_ENABLE_PASSWORD` — mật khẩu **thật** của service account trên thiết bị.

> `.env` chứa plaintext secret — chỉ phù hợp bootstrap nhanh. Khi lên production ổn định, chuyển sang Ansible Vault hoặc secret manager (Vault/1Password/AWS Secrets Manager...) và bơm biến môi trường qua đó thay vì file `.env` nằm trên đĩa.

## 6. Network

Container chạy với `network_mode: host` — dùng thẳng network stack của server, không cần join docker network riêng. Chỉ cần server ping/SSH được tới thiết bị, container sẽ SSH được (không phải cấu hình thêm docker network/firewall rule nào khác).

## 7. Quy trình chạy

```bash
# 1. Lint — bắt lỗi cú pháp/style trước khi chạm thiết bị
docker compose --profile lint run --rm lint

# 2. Dry-run — xem trước những gì sẽ đổi, KHÔNG apply
docker compose --profile dry-run run --rm dry-run

# 3. Apply thật lên thiết bị
docker compose up --build push
```

`push` chính là bước mà job `push` trong [`network-cicd-1-push.yml`](../../../.github/workflows/network-cicd-1-push.yml) chạy khi PR merge vào `main` — nếu server này đóng vai trò self-hosted GitHub Actions runner, workflow có thể gọi thẳng `docker compose up --build push` thay vì cài `ansible-galaxy`/`ansible-playbook` trực tiếp lên runner.

## 8. Verify

```bash
ssh backup_user@<ip-thiết-bị>
show running-config | include name-server
```

## 9. Vận hành liên tục (tuỳ chọn)

- Đăng ký server làm **self-hosted runner** cho repo, để CI tự SSH vào server này chạy `docker compose up --build push` mỗi khi merge — giữ đúng mô hình GitOps Push, chỉ khác là bước push chạy trong container thay vì cài thẳng lên runner.
- Nếu muốn chạy thủ công định kỳ/theo lịch: bọc bước 7.3 trong `systemd` timer hoặc `cron`, log ra file để giữ audit trail song song với Git history.

## 10. Bảo mật

- Không commit `.env` (đã có `.gitignore` chặn `*.env` ở repo — kiểm tra lại nếu tuỳ biến).
- User chạy `docker` coi như có quyền root trên host (docker group tương đương root) — giới hạn ai được thêm vào group `docker` trên server này.
- Đổi mật khẩu `backup_user` định kỳ, giữ `LAB_ENABLE_PASSWORD`/`LAB_DEVICE_PASSWORD` tách biệt secret manager, không hardcode trong Git.
