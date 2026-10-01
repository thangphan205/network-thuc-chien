FROM debian:12-slim
# ==============================================================================
# CHU Y: client dung glibc (Debian), KHONG dung musl (Alpine).
#
# Tap nay day ve resolver, ma resolver la mot phan cua libc — doi libc la doi
# hanh vi. Ba dieu duoi day DA DUOC DO trong chinh lab nay, khong phai suy doan:
#
#   1. /etc/hosts de len DNS (KB3): musl va glibc GIONG NHAU. Alpine co ship file
#      /etc/nsswitch.conf, nhung musl BO QUA no — ep "hosts: dns" thi musl VAN
#      doc /etc/hosts. Voi glibc, doi dong do la doi that.
#
#   2. Nhieu nameserver, cai dau CHET: khac biet lon nhat.
#        musl  -> hoi SONG SONG tat ca nameserver, tra loi sau ~0 ms.
#        glibc -> hoi LAN LUOT, cho het timeout cua cai dau, mat ~3000 ms.
#      Day la ly do mot dich vu chuyen tu Alpine sang Debian co the "bong dung
#      cham" ma khong ai doi gi ve mang.
#
#   3. search/ndots: glibc thu tung hau to trong `search` theo thu tu, va mot
#      cau tra loi NXDOMAIN dut khoat se lam no DUNG LAI (xem MR3).
#
# Hoc vien gap Ubuntu/RHEL ngoai doi, nen lab phai khop glibc.
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
        dnsutils curl iproute2 iputils-ping tcpdump nscd procps ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# nscd = bo dem DNS nam NGAY TREN MAY CLIENT. Mac dinh KHONG chay; chi MR5 bat len.
#   - Thieu 2 thu muc runtime nay, nscd thoat ngay voi "child exited with status 1".
#   - TTL 60 giay: du lau de quan sat "sua roi ma van sai", du ngan de xem no het
#     han ngay trong buoi hoc.
RUN mkdir -p /var/run/nscd /var/db/nscd \
 && sed -i 's/^\(\s*positive-time-to-live\s\+hosts\s\+\).*/\1 60/' /etc/nscd.conf

COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod 0755 /usr/local/bin/monitor.sh
# Khong can CMD: docker-compose.yml da dat `command: sleep infinity`
