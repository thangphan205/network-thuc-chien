#!/bin/bash

echo "🚀 Đang tiến hành xóa cụm K8s Lab..."

echo "Đang xóa controlplane..."
multipass delete controlplane

echo "Đang xóa worker1..."
multipass delete worker1

echo "Đang xóa worker2..."
multipass delete worker2

echo "🧹 Đang dọn dẹp (purge) các máy ảo đã bị xóa khỏi thùng rác..."
multipass purge

echo "✅ Đã xóa toàn bộ máy ảo và giải phóng dung lượng."
