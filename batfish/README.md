# 🦇 Batfish Thực Chiến — Phân Tích & Kiểm Thử Cấu Hình Mạng Tự Động (NetDevOps & CI/CD)

> **Mô phỏng và kiểm thử an toàn toàn bộ Data Plane / Control Plane của hạ tầng mạng đa thiết bị (Cisco, Arista, Juniper, Palo Alto, Cumulus...) trước khi triển khai thực tế (Pre-deployment Validation).**

---

## 💡 Batfish là gì và Tại sao NetDevOps cần Batfish?

Trong quy trình tự động hóa mạng (Network Automation) truyền thống, kĩ sư mạng thường áp dụng Ansible, Python hay Nornir để đẩy nhanh cấu hình (Push Config) lên hàng trăm router/switch. Tuy nhiên:
* **Rủi ro cực lớn**: Nếu một dòng lệnh ACL bị viết nhầm thứ tự hoặc IP neighbor BGP bị typo, cả mạng Production có thể bị **sập ngay lập tức (Outage)**.
* **GNS3 / EVE-NG quá nặng**: Giả lập thiết bị thật tốn hàng chục GB RAM và CPU, không thể tích hợp nhanh vào quy trình kiểm thử tự động CI/CD Pipeline trên Cloud.

### 🛡️ Giải pháp từ Batfish:
Batfish (được phát triển bởi Intentionet & cộng đồng mã nguồn mở tại [github.com/batfish/batfish](https://github.com/batfish/batfish)) là công cụ phân tích cấu hình mạng tĩnh (Static Configuration Analysis):
1. **No Live Devices Needed**: Batfish chỉ đọc file cấu hình thô (`.cfg`, `.conf`) offline.
2. **Build Virtual Control/Data Plane**: Batfish dựng lại bảng tuyến đường (Routing Tables), bảng ARP, ACLs, BGP/OSPF sessions trong bộ nhớ chỉ trong vài giây.
3. **Query & Audit via Pybatfish**: Cho phép đặt câu hỏi bằng Python như *"App Server có nói chuyện được với DB Server không?"*, *"Thay đổi này có làm đứt kết nối nào không?"*.

---

## 🏛️ Sơ Đồ Mô Hình Mạng Doanh Nghiệp trong Lab

Mô hình mạng doanh nghiệp trong bài lab này đại diện cho kiến trúc Multi-zone tiêu chuẩn:

```
                          [ Internet / ISP ]
                                  │ (eBGP)
                           ┌──────┴──────┐
                           │   fw-edge   │ (Edge Firewall & Router)
                           └──────┬──────┘
                                  │ (OSPF Area 0)
                    ┌─────────────┴─────────────┐
             ┌──────┴──────┐             ┌──────┴──────┐
             │   r1-core   ├─────────────┤   r2-core   │ (Core Routers & iBGP)
             └──────┬──────┘   (iBGP)    └──────┬──────┘
                    │                           │
                    └─────────────┬─────────────┘
                           ┌──────┴──────┐
                           │  sw-dist1   │ (Distribution Switch)
                           └──────┬──────┘
              ┌───────────────────┼───────────────────┐
              │                   │                   │
      [ App Subnet ]       [ DB Subnet ]       [ Mgmt Subnet ]
       VLAN 10 (App)        VLAN 20 (DB)        VLAN 99 (Mgmt)
       10.10.10.0/24       10.20.20.0/24       10.99.0.0/24
```

### Các Thành Phần Mạng:
* **`fw-edge`**: Edge Firewall / Router lọc traffic bằng ACL `SEC-ACL-IN`.
* **`r1-core` & `r2-core`**: Cặp Core Router chạy OSPF Area 0 nội bộ và iBGP (AS 65000).
* **`sw-dist1`**: Switch phân phối chứa các Gateway Subnet (VLAN 10: App, VLAN 20: DB, VLAN 99: Mgmt).

---

## 📂 Cấu Trúc Thư Mục Module `batfish/`

```text
batfish/
├── README.md                      # Tài liệu hướng dẫn thực hành (File này)
├── docker-compose.yml             # Khởi tạo Batfish Server Container
├── requirements.txt               # Các thư viện Python Client (pybatfish, rich, pandas)
├── networks/                      # Chứa các Snapshots cấu hình mạng
│   ├── base_network/              # Trạng thái mạng Production đang chạy ổn định
│   │   └── configs/               # File cấu hình Cisco IOS (.cfg) của 4 thiết bị
│   └── proposed_network/          # Trạng thái đề xuất thay đổi (Pull Request) chứa lỗi
└── scripts/                       # 5 Script Python demo kịch bản thực tế
    ├── 01_parse_and_inventory.py  # Kịch bản 1: Parse cấu hình & Trích xuất Inventory
    ├── 02_reachability_traceroute.py # Kịch bản 2: Virtual Traceroute & Reachability Test
    ├── 03_security_acl_analysis.py   # Kịch bản 3: Phân tích an toàn bảo mật & Lỗi ACL
    ├── 04_impact_analysis_diff.py    # Kịch bản 4: Differential Analysis (Guardrail CI/CD)
    └── 05_failure_simulation.py      # Kịch bản 5: Mô phỏng sự cố Chaos Failure (What-If)
```

---

## 🚀 Hướng Dẫn Khởi Tạo Môi Trường Lab

### Bước 1: Khởi chạy Batfish Server bằng Docker

Khởi chạy container Batfish ở background:
```bash
cd batfish
docker compose up -d
```

Kiểm tra trạng thái container:
```bash
docker compose ps
```
*(Cổng `9997` và `9996` sẽ mở để giao tiếp với Client)*

### Bước 2: Tạo Môi trường Python Virtualenv

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## 🧪 Chi Tiết 5 Kịch Bản Demo Thực Hành

### 📝 Kịch bản 1: Parse Cấu hình & Trích xuất Danh mục (Inventory)
Trích xuất tự động danh sách Interface, IP addresses, và cấu hình BGP từ các file cấu hình Cisco IOS offline mà không cần kết nối tới thiết bị thật.

```bash
python scripts/01_parse_and_inventory.py
```

---

### 🔍 Kịch bản 2: Phân tích Khả năng Kết nối & Virtual Traceroute
Mô phỏng đường đi của gói tin TCP cổng `5432` từ App Server (`10.10.10.50`) tới Database Server (`10.20.20.100`).

```bash
python scripts/02_reachability_traceroute.py
```
> **Kết quả kỳ vọng**: Chặng đi từ `sw-dist1` ➔ `r1-core` ➔ `fw-edge` thành công (`ACCEPTED`).

---

### 🛡️ Kịch bản 3: Phân tích An toàn Bảo mật & Lỗi ACL (Shadowed Rules)
Phát hiện các dòng ACL bị dư thừa hoặc bị che khuất (Unreachable / Shadowed ACL rules) do kỹ sư sắp xếp sai thứ tự câu lệnh.

```bash
python scripts/03_security_acl_analysis.py
```
> **Kết quả kỳ vọng**: Cảnh báo dòng `permit tcp 10.10.10.0 ...` trên `fw-edge` trong `proposed_network` bị che khuất bởi dòng `deny ip any 10.20.20.0/24`.

---

### 🚨 Kịch bản 4: Differential Analysis (Tác động Thay đổi) — CI/CD Guardrail
**Kịch bản quan trọng nhất!** So sánh snapshot Production (`base_network`) với Pull Request đề xuất (`proposed_network`).

```bash
python scripts/04_impact_analysis_diff.py
```
> **Kết quả kỳ vọng**: Batfish phát hiện:
> 1. Kết nối App Server ➔ Database Server bị **MẤT (LOST REACHABILITY)**.
> 2. BGP Session trên `r2-core` bị **SẬP (DISCONNECTED)** do typo IP Neighbor `1.1.1.99`.
> 3. Script tự động `exit(1)` để **CHẶN PULL REQUEST** không cho merge code!

---

### 💥 Kịch bản 5: Mô phỏng Sự cố Mạng (Failure Simulation / Chaos Test)
Giả lập tình huống đứt link `GigabitEthernet0/2` trên `r1-core` và kiểm tra khả năng hội tụ tuyến đường (OSPF Failover) qua `r2-core`.

```bash
python scripts/05_failure_simulation.py
```
> **Kết quả kỳ vọng**: Traffic tự động chuyển hướng qua `r2-core` mà không bị gián đoạn.

---

## 🔄 Tích hợp Batfish vào GitHub Actions (CI/CD Pipeline)

Dưới đây là file mẫu `.github/workflows/batfish-ci.yml` để tự động hóa kiểm thử cấu hình mạng trong quy trình GitOps:

```yaml
name: Network Configuration Pre-deployment CI

on:
  pull_request:
    branches: [ main ]

jobs:
  batfish-validation:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Start Batfish Container
        run: |
          docker run -d -p 9997:9997 -p 9996:9996 batfish/batfish

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install Dependencies
        run: |
          pip install -r batfish/requirements.txt

      - name: Run Batfish Differential Analysis Test
        run: |
          cd batfish
          python scripts/04_impact_analysis_diff.py
```

---

## 🎯 Tóm tắt Giá trị đem lại của Batfish

| Tiêu chí | Kiểm thử truyền thống (Manual / Live Lab) | Kiểm thử với Batfish (Automated Static Analysis) |
| :--- | :--- | :--- |
| **Thời gian kiểm thử** | Vài giờ tới vài ngày | **Chỉ tốn vài GIÂY** |
| **Tài nguyên phần cứng** | Cần máy chủ khủng (EVE-NG/GNS3) | **Rất nhẹ (chạy được trên GitHub Actions/Docker)** |
| **Phát hiện lỗi ACL/BGP** | Dễ bỏ sót khi cấu hình phức tạp | **Chính xác 100% bằng mô hình toán học** |
| **Rủi ro sập Production** | Cao khi thao tác thủ công | **BẰNG KHÔNG (Triển khai an toàn 100%)** |
