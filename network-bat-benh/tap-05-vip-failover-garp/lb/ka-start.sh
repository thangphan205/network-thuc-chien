#!/bin/sh
# Bật lại Keepalived. Tham số 1 (tuỳ chọn) = file cấu hình.
#   ka-start                                           -> cấu hình mặc định (preempt)
#   ka-start /etc/keepalived/keepalived-nopreempt.conf -> bản nopreempt
#
# ⚠️ KHÔNG dò bằng `ps aux | grep keepalived`: chính lệnh này mang tham số
#    "/etc/keepalived/keepalived.conf" — chuỗi đó CHỨA chữ "keepalived" nên
#    grep khớp vào chính nó, script tưởng keepalived đang chạy rồi thoát ngay
#    mà không khởi động gì cả. Phải khớp CHÍNH XÁC tên tiến trình.
#
# ⚠️ Đồng thời phải loại tiến trình ZOMBIE (<defunct>): pgrep vẫn khớp với xác
#    keepalived đã chết nhưng chưa được thu dọn.
CONF="${1:-/etc/keepalived/keepalived.conf}"

dang_chay() {
    for p in $(pgrep -x keepalived 2>/dev/null); do
        # Trường thứ 3 của /proc/<pid>/stat là trạng thái; 'Z' = zombie
        [ "$(awk '{print $3}' "/proc/$p/stat" 2>/dev/null)" != "Z" ] && return 0
    done
    return 1
}

dang_chay && exit 0
exec keepalived -D -f "$CONF"
