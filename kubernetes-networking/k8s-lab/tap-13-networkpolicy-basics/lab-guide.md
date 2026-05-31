# Lab Tập 13: NetworkPolicy cơ bản — Default Deny và Ingress Policy

Tập này thực hành viết NetworkPolicy từ đầu với thứ tự đúng và test từng bước.

## 📖 Đề bài & Kịch bản thực tế
Giả sử bạn được giao quản lý hệ thống mạng cho một dự án quan trọng của công ty, chạy trong namespace `production`. Dự án gồm có một ứng dụng web (`frontend`) và một API server (`backend`).

**Yêu cầu an ninh từ Giám đốc bảo mật (CISO):**
1. **Zero Trust (Không tin tưởng ai):** Mặc định phải khóa chặt toàn bộ kết nối đi vào (Ingress) của tất cả các dịch vụ trong cụm.
2. **Đặc quyền tối thiểu (Least Privilege):** Chỉ cho phép duy nhất ứng dụng `frontend` được phép kết nối tới cổng `8080` của ứng dụng `backend`.
3. **Phòng chống nội gián:** Nếu có một Pod lạ (`attacker`) bằng cách nào đó lọt được vào namespace, nó cũng tuyệt đối không được phép gọi vào `backend`.
4. **Đảm bảo vận hành (Critical):** Hệ thống dù có bị khóa chặt đến đâu cũng tuyệt đối không được làm "chết" chức năng phân giải tên miền (DNS) của Kubernetes.

Nhiệm vụ của bạn là sử dụng Kubernetes NetworkPolicy để hóa giải từng yêu cầu trên!

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 9.
- Không có NetworkPolicy nào đang active trong namespace `production` (xóa nếu có từ tập trước).

---

## 🔬 Thực nghiệm 1: Deploy namespace và Pods

**🎯 Mục tiêu:**
- Khởi tạo môi trường mạng cho bài lab với các Pod `frontend` và `backend`.
- Chứng minh nguyên tắc **Default Allow** của Kubernetes: Khi chưa có NetworkPolicy nào, mọi Pod đều có thể tự do kết nối với nhau mà không bị cấm cản.

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. Tạo namespace `production`:
   ```bash
   kubectl create namespace production 2>/dev/null || true
   ```

2. Deploy frontend, backend và Service:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: frontend
     labels:
       app: frontend
       tier: web
   spec:
     nodeName: worker1
     containers:
     - name: web
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: backend
     labels:
       app: backend
       tier: api
   spec:
     nodeName: worker2
     containers:
     - name: api
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "8080"]
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: backend-svc
   spec:
     selector:
       app: backend
     ports:
     - port: 8080
       targetPort: 8080
   EOF
   kubectl -n production wait --for=condition=Ready pod/frontend pod/backend --timeout=90s
   ```

3. Test baseline (không có policy → tất cả pass):
   ```bash
   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 port succeeded! ✅
   ```

---

## 🔬 Thực nghiệm 2: Apply Default Deny Ingress

**🎯 Mục tiêu:**
- Thiết lập chốt chặn an ninh đầu tiên: Khóa toàn bộ Ingress (chiều vào) trong namespace.
- Áp dụng nguyên tắc **Least Privilege** (Đặc quyền tối thiểu) bằng cách viết rule chỉ "đục lỗ" cho phép đúng Pod `frontend` kết nối vào `backend`.

**Trên `controlplane`:**

1. Apply default deny ingress cho toàn namespace:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny-ingress
   spec:
     podSelector: {} # Để trống {} nghĩa là chọn TẤT CẢ các Pod trong namespace
     policyTypes:
     - Ingress       # Khai báo quản lý Ingress. Vì không có luật 'ingress:' nào ở dưới -> MẶC ĐỊNH CẤM TẤT CẢ
   EOF
   ```

2. Test — backend ingress bị deny:
   ```bash
   kubectl -n production exec frontend -- nc -zv -w 3 backend-svc 8080
   # (timeout) ← Backend ingress bị deny ✅
   ```

3. Apply allow rule cho frontend → backend:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-frontend
   spec:
     podSelector:
       matchLabels:
         app: backend     # Áp dụng lớp khiên bảo vệ này lên Pod 'backend'
     policyTypes:
     - Ingress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: frontend # Phía gửi: Chỉ cho phép các Pod có nhãn 'app: frontend'
       ports:
       - protocol: TCP
         port: 8080        # Phía nhận: Chỉ mở duy nhất cổng 8080
   EOF
   ```

4. Test lại — frontend được vào:
   ```bash
   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 succeeded! ✅
   ```

---

## 🔬 Thực nghiệm 3: Deploy attacker pod và verify bị chặn

**🎯 Mục tiêu:**
- Giả lập một mối đe dọa nội bộ (Internal Threat) bằng cách tạo một Pod `attacker` lạ, không có nhãn hợp lệ.
- Kiểm chứng xem hệ thống an ninh Ingress vừa thiết lập ở Thực nghiệm 2 có thực sự chặn đứng được các nỗ lực xâm nhập trái phép hay không.

**Trên `controlplane`:**

1. Deploy attacker pod (không có label app=frontend):
   ```bash
   kubectl run attacker -n production --image=nicolaka/netshoot -- sleep infinity
   kubectl -n production wait --for=condition=Ready pod/attacker --timeout=60s
   ```

2. Test từ attacker — phải bị chặn:
   ```bash
   BACKEND_IP=$(kubectl -n production get pod backend -o jsonpath='{.status.podIP}')
   kubectl -n production exec attacker -- nc -zv -w 3 $BACKEND_IP 8080
   # (timeout) ← Attacker bị chặn ✅ (không có label app=frontend)
   ```

3. Test từ frontend — vẫn qua:
   ```bash
   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 succeeded! ✅
   ```

---

## 🔬 Thực nghiệm 4: Demo DNS break và fix

**🎯 Mục tiêu:**
- Trải nghiệm lỗi kinh điển nhất khi làm NetworkPolicy: Chặn nhầm Egress (chiều ra) làm hỏng hoàn toàn tính năng phân giải tên miền (CoreDNS).
- Học cách sửa lỗi bằng tư duy chuẩn xác: **Luôn ưu tiên Allow DNS port 53 trước tiên**.

**Trên `controlplane`:**

1. Apply default deny egress (mạnh nhất):
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny-egress
   spec:
     podSelector: {} # Áp dụng cho TẤT CẢ các Pod
     policyTypes:
     - Egress        # Quản lý Egress nhưng không có khối 'egress:' -> MẶC ĐỊNH CẤM MỌI TRAFFIC ĐI RA
   EOF
   ```

2. DNS bị break:
   ```bash
   kubectl -n production exec frontend -- nslookup backend-svc
   # ;; connection timed out; no servers could be reached ❌
   ```

3. Fix — Apply DNS allow rule **trước**:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-dns
   spec:
     podSelector: {} # Mở đường cho TẤT CẢ các Pod trong namespace
     policyTypes:
     - Egress
     egress:
     - ports:        # Không giới hạn IP đích đến, chỉ mở dựa trên port
       - protocol: UDP
         port: 53    # Port chuẩn của DNS (CoreDNS)
       - protocol: TCP
         port: 53
   EOF
   ```

4. DNS hoạt động trở lại:
   ```bash
   kubectl -n production exec frontend -- nslookup backend-svc
   # Name: backend-svc.production.svc.cluster.local ✅
   ```

5. Nhưng frontend → backend vẫn chưa được (egress bị deny):
   ```bash
   kubectl -n production exec frontend -- nc -zv -w 3 backend-svc 8080
   # (timeout) ← Egress từ frontend bị deny
   ```

6. Allow egress từ frontend đến backend:
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-frontend-egress
   spec:
     podSelector:
       matchLabels:
         app: frontend # Cấp quyền đi ra (egress) cho Pod 'frontend'
     policyTypes:
     - Egress
     egress:
     - to:
       - podSelector:
           matchLabels:
             app: backend # Hướng đích đến: cho phép gọi tới các Pod 'backend'
       ports:
       - protocol: TCP
         port: 8080       # Phải chỉ định rõ gọi vào port nào
   EOF

   kubectl -n production exec frontend -- nc -zv backend-svc 8080
   # Connection to backend-svc 8080 succeeded! ✅
   ```

---

## 🧹 Dọn dẹp (giữ namespace production cho tập tiếp)

```bash
kubectl -n production delete networkpolicy --all
kubectl -n production delete pod attacker
# Giữ frontend và backend cho Tập 14
```

---

## ✅ Tổng kết

1. **Không có policy = default allow:** Pod không bị select bởi bất kỳ policy nào thì không bị restrict gì.
2. **Thứ tự đúng:** Allow DNS trước → Allow egress cần thiết → Default deny ingress → Allow ingress cụ thể → Default deny egress.
3. **DNS must always be allowed:** Quên allow port 53 UDP/TCP → mọi DNS lookup fail → app không làm gì được.
4. **Test matrix:** Sau mỗi policy, test từng cặp source→dest để xác nhận đúng behavior.
