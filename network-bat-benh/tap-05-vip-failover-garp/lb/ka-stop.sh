#!/bin/sh
# Tắt Keepalived bằng SIGKILL.
#
# VÌ SAO PHẢI LÀ SIGKILL (-9)?
#   Nhận SIGTERM, keepalived tắt "lịch sự": nó phát một VRRP advertisement với
#   priority = 0 để chủ động nhường quyền. Node BACKUP thấy priority 0 sẽ lên
#   MASTER NGAY LẬP TỨC và tự phát GARP -> ca bệnh "quên GARP" tự khỏi trong
#   khoảng 0.5 giây, không kịp quan sát.
pkill -9 keepalived 2>/dev/null
# Gỡ VIP nếu keepalived chưa kịp dọn (SIGKILL thì nó không dọn gì cả)
[ -n "$1" ] && ip addr del "$1"/24 dev eth0 2>/dev/null
exit 0
