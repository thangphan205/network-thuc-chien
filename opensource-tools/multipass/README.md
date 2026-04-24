---
marp: true
theme: gaia
_class: lead
paginate: true
backgroundColor: #fff
backgroundImage: url('https://marp.app/assets/hero-background.jpg')
---

# **Multipass**
### Ảo hóa siêu tốc cho Network & Security Engineer

**Thang**
@NetworkThucChien


---

# Vấn đề của kỹ sư hạ tầng?

- **VMware / VirtualBox:** Quá nặng, tốn tài nguyên GUI, cài đặt thủ công (ISO) mất thời gian.
- **Docker:** Rất nhanh, nhưng dùng chung kernel với máy host.
  - Hạn chế khi can thiệp sâu vào **System Networking** (iptables, routing).
  - Khó khăn khi test các service yêu cầu **systemd** hoàn chỉnh.

> **Giải pháp:** Cần một máy ảo (Full VM) nhưng có tốc độ và cách quản lý như Container.

---

# Multipass là gì?

- Một công cụ CLI từ **Canonical** để quản lý các thực thể Ubuntu.
- **Tốc độ:** Khởi chạy một server Ubuntu sạch chỉ trong vài giây.
- **Tối ưu:** Tự động hóa việc tải image, cấu hình tài nguyên và mạng.
- **Giao diện:** 100% dòng lệnh (CLI-First).

---

# Kiến trúc vận hành

Multipass tận dụng các **Native Hypervisor** để đạt hiệu năng cao nhất:

- **Windows:** Hyper-V / VirtualBox.
- **Linux:** KVM / QEMU.
- **macOS:** HyperKit / QEMU (Tối ưu cho Apple Silicon M1/M2/M3).

*Kết quả: Một máy ảo Ubuntu thực thụ với Kernel riêng biệt nhưng khởi động nhanh như chớp.*

---

# Bảng So sánh Hiệu năng & Đặc điểm

| Tiêu chí | Multipass | Docker | Vagrant (VirtualBox) | VMware/ESXi |
| :--- | :--- | :--- | :--- | :--- |
| **Mức độ ảo hóa** | Full OS (Kernel riêng) | Container (Chung Kernel) | Full OS (Kernel riêng) | Bare-metal/Type 1 |
| **Tốc độ khởi động** | Siêu nhanh (~5-10s) | Tức thì (~1s) | Chậm (~30-60s) | Rất chậm |
| **Tiêu hao tài nguyên**| Rất thấp (Native Hypervisor)| Thấp nhất | Cao (Có overhead GUI/OS) | Rất cao |
| **Độ sâu Lab Mạng** | Tuyệt đối (Can thiệp routing/iptables)| Hạn chế (Thiếu systemd/kernel modules)| Rất tốt (Nhưng nặng nề)| Tuyệt đối |
| **Hệ điều hành hỗ trợ**| Chỉ Ubuntu | Đa dạng (Linux) | Đa dạng (Linux, Windows...)| Đa dạng |


---

# Ứng dụng trong Network & Security

1. **Test Network Automation:** Chạy các script cấu hình switch/router trên các node sạch.
2. **Sandbox cho Open-Source:** - Dựng backend `tac_plus-ng` để test **tacacs-ng-ui**.
   - Giả lập môi trường mạng thực tế cho **NetConsole**.
3. **Phân tích mã độc & Security Lab:** Cô lập hoàn toàn với máy host, xóa sạch dấu vết (Purge) chỉ với 1 lệnh.

---

# Cài đặt & Mã nguồn

- **Trang chủ & Tài liệu:** [https://canonical.com/multipass](https://canonical.com/multipass)
- **Mã nguồn (GitHub):** [canonical/multipass](https://github.com/canonical/multipass)

### Cài đặt siêu tốc:

**macOS (Homebrew - Khuyên dùng):**
```bash
brew install --cask multipass
```

**Windows:**
Tải file `.exe` cài đặt trực tiếp từ trang chủ. Yêu cầu bật Hyper-V.

**Linux (Snap):**
```bash
sudo snap install multipass
```

---

# Lệnh cơ bản (Cheatsheet)

```bash
# Tìm kiếm các phiên bản Ubuntu
$ multipass find

# Khởi chạy VM LTS (Long-term support)
$ multipass launch lts

# Khởi chạy VM với cấu hình tùy chỉnh
$ multipass launch -c 2 -m 4G -n security-lab

# Truy cập vào Shell của máy ảo
$ multipass shell security-lab

# Mount thư mục dự án vào VM
$ multipass mount ./projects security-lab:/home/ubuntu/app

# Dọn dẹp sạch sẽ
$ multipass delete security-lab && multipass purge