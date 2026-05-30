# Lab Tập 14: Cross-namespace Policy — AND vs OR

Tập này chứng minh sự khác biệt sống còn giữa AND và OR logic trong NetworkPolicy YAML bằng cách demo rogue pod vào được hay không.

## 📖 Đề bài & Kịch bản thực tế
Hệ thống `backend` của bạn đang chạy an toàn trong namespace `production`. Bây giờ, đội vận hành (Ops) yêu cầu bạn mở một chính sách tường lửa chéo (Cross-namespace) để hệ thống giám sát **Prometheus** (nằm ở namespace `monitoring`) có thể truy cập vào cổng `9090` của backend nhằm thu thập số liệu (metrics).

**Yêu cầu an ninh từ Giám đốc bảo mật (CISO):**
- Chỉ cấp quyền truy cập một cách cực kỳ khắt khe (AND logic): **CHỈ CÓ** Pod mang nhãn `role: prometheus` **VÀ** bắt buộc phải nằm trong namespace `monitoring` mới được phép truy cập.
- Hệ thống phải miễn nhiễm với các Pod giả mạo (Rogue Pod): Ví dụ một Pod lạ trà trộn vào namespace `monitoring` nhưng không có nhãn prometheus, hoặc một Pod có nhãn prometheus nhưng nằm ở namespace khác đều tuyệt đối không được phép lọt qua.

Một đồng nghiệp của bạn vừa viết xong một đoạn YAML NetworkPolicy và khẳng định nó rất an toàn. Nhiệm vụ của bạn là kiểm chứng xem file YAML đó có thực sự chặn được các Pod giả mạo hay không, tìm ra lỗ hổng và học cách viết lại cho chuẩn xác nhất!

**Mô hình mục tiêu:**
```mermaid
graph TD
    subgraph NS_MON [Namespace: monitoring]
        Prom["✅ Pod: prometheus<br>(role=prometheus)"]
        Rogue["❌ Pod: rogue<br>(không có nhãn)"]
    end
    
    subgraph NS_OTHER [Namespace: any-other]
        FakeProm["❌ Pod: fake-prom<br>(role=prometheus)"]
    end

    subgraph NS_PROD [Namespace: production]
        Frontend["✅ Pod: frontend<br>(app=frontend)"]
        Attacker["❌ Pod: attacker<br>(từ Tập 13)"]
        
        Svc["Service: backend-metrics<br>:9090"]
        Backend["🎯 Pod: backend<br>Port: 8080 & 9090"]
        
        Svc --> Backend
        Frontend -->|"Được phép (Port 8080)"| Backend
        Attacker -.->|"Bị chặn (Port 8080)"| Backend
    end

    Prom -->|"Được phép (AND Logic - Port 9090)"| Svc
    Rogue -.->|"Bị chặn (Sai Pod Label)"| Svc
    FakeProm -.->|"Bị chặn (Sai Namespace)"| Svc

    style Prom fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#fff
    style Frontend fill:#064e3b,stroke:#34d399,stroke-width:2px,color:#fff
    style Rogue fill:#7f1d1d,stroke:#f87171,stroke-width:2px,color:#fff
    style FakeProm fill:#7f1d1d,stroke:#f87171,stroke-width:2px,color:#fff
    style Attacker fill:#7f1d1d,stroke:#f87171,stroke-width:2px,color:#fff
    style Backend fill:#1e3a8a,stroke:#3b82f6,stroke-width:2px,color:#fff
```

## 🛠 Yêu cầu chuẩn bị
- Cụm K8s với Calico từ Tập 9.
- Không có NetworkPolicy nào đang active trong `production`.

---

## 🔬 Thí nghiệm 1: Deploy môi trường test

> Trước tiên chúng ta sẽ dựng toàn bộ hạ tầng cho bài lab: tạo namespace, deploy backend cùng Service trong `production`, rồi deploy prometheus và rogue pod trong `monitoring`. Sau đó kiểm tra baseline để xác nhận chưa có policy nào chặn traffic.

**SSH vào `controlplane`:**

```bash
multipass shell controlplane
```

1. **Tạo namespaces và gán label.**
   Chúng ta cần label cho cả hai namespace vì `namespaceSelector` trong NetworkPolicy chỉ hoạt động dựa trên label — không phải tên namespace.
   ```bash
   kubectl create namespace production 2>/dev/null || true
   kubectl create namespace monitoring 2>/dev/null || true

   # BẮT BUỘC: label namespace để namespaceSelector hoạt động
   kubectl label namespace monitoring name=monitoring --overwrite
   kubectl label namespace production name=production --overwrite
   ```

2. **Deploy backend với metrics endpoint và Service trong `production`.**
   Pod backend lắng nghe trên port `9090` — đây là endpoint mà Prometheus sẽ scrape. Service `backend-metrics` đóng vai trò entry point từ bên ngoài namespace.
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: backend
     labels:
       app: backend
   spec:
     nodeName: worker1
     containers:
     - name: app
       image: nicolaka/netshoot
       command: ["nc", "-lk", "-p", "9090"]
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: backend-metrics
   spec:
     selector:
       app: backend
     ports:
     - port: 9090
       targetPort: 9090
   EOF
   ```

3. **Deploy prometheus và rogue pod trong `monitoring`.**
   `prometheus` có label `role: prometheus` — đây là pod hợp lệ. `rogue` không có label nào — đây là kẻ xâm nhập mà chúng ta muốn chặn.
   ```bash
   kubectl apply -n monitoring -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata:
     name: prometheus
     labels:
       role: prometheus
   spec:
     nodeName: worker2
     containers:
     - name: prom
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: rogue
   spec:
     nodeName: worker2
     containers:
     - name: shell
       image: nicolaka/netshoot
       command: ["sleep", "infinity"]
   EOF
   ```

4. **Chờ tất cả pod sẵn sàng.**
   Đừng chuyển bước nếu lệnh này báo lỗi hoặc timeout — pod chưa ready thì kết quả test sẽ không chính xác.
   ```bash
   kubectl -n production wait --for=condition=Ready pod/backend --timeout=60s
   kubectl -n monitoring wait --for=condition=Ready pod/prometheus pod/rogue --timeout=60s
   ```

5. **Verify baseline — chưa có policy nào, tất cả đều kết nối được.**
   Đây là trạng thái "mặc định mở" của Kubernetes. Kết quả này xác nhận môi trường hoạt động đúng trước khi chúng ta thêm policy.
   ```bash
   kubectl -n monitoring exec prometheus -- nc -zv backend-metrics.production.svc.cluster.local 9090
   # Connection succeeded! ✅ (default allow — chưa có policy)

   kubectl -n monitoring exec rogue -- nc -zv backend-metrics.production.svc.cluster.local 9090
   # Connection succeeded! ✅ (default allow — chưa có policy)
   ```
   > Cả hai đều vào được — đây là hành vi bình thường. Nguy hiểm bắt đầu khi chúng ta apply policy sai ở bước tiếp theo.

---

## 💥 Thí nghiệm 2: Apply OR policy (buggy) và chứng minh lỗ hổng

> Đây là phần cốt lõi của bài lab. Chúng ta sẽ apply đúng đoạn YAML mà "đồng nghiệp" đã viết — trông có vẻ đúng nhưng thực ra có lỗ hổng nghiêm trọng do dấu `-` đặt sai chỗ. Hãy quan sát kỹ kết quả test để thấy rogue pod vẫn lọt qua được.

**Trên `controlplane`:**

1. **Apply default deny cho `production`.**
   Bước này khóa toàn bộ ingress traffic vào namespace `production`. Từ đây, mọi kết nối sẽ bị chặn trừ khi có policy cho phép tường minh.
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: default-deny
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
   EOF
   ```

2. **Apply policy OR (buggy) — dấu `-` tạo 2 items riêng biệt.**
   Nhìn qua YAML này trông khá hợp lý: có cả `namespaceSelector` lẫn `podSelector`. Nhưng hãy chú ý dấu `-` trước `podSelector` — đó chính là điểm chết người. Kubernetes sẽ diễn giải đây là **OR** (một trong hai điều kiện thỏa mãn là đủ), không phải AND.
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-prometheus-OR-bug
   spec:
     podSelector:
       matchLabels:
         app: backend
     policyTypes:
     - Ingress
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: monitoring
       - podSelector:              # ← Dấu "-" này = ITEM MỚI = OR!
           matchLabels:
             role: prometheus
       ports:
       - protocol: TCP
         port: 9090
   EOF
   ```

3. **Test: Rogue pod phải bị chặn — nhưng thực ra KHÔNG bị chặn.**
   Đây là khoảnh khắc "aha". Rogue pod không có nhãn nào cả, nhưng vẫn vào được vì policy chỉ cần thỏa điều kiện 1: nằm trong namespace `monitoring` — và rogue đang ở đó.
   ```bash
   kubectl -n monitoring exec rogue -- nc -zv backend-metrics.production.svc.cluster.local 9090
   # Connection succeeded! ← BUG! Rogue vào được vì match namespace monitoring
   ```

4. **Test: Prometheus cũng vào được — nhưng vì lý do sai.**
   Prometheus thông mạng trông có vẻ đúng, nhưng thực ra nó thông vì điều kiện `namespaceSelector` mở toang, không phải vì `podSelector` chặt chẽ. Điều này che giấu lỗ hổng.
   ```bash
   kubectl -n monitoring exec prometheus -- nc -zv backend-metrics.production.svc.cluster.local 9090
   # Connection succeeded! ✅ (nhưng lý do thông mạng là sai)
   ```
   > **Phân tích bản chất:** Prometheus vào được thực tế là do điều kiện thứ nhất (`namespaceSelector` match namespace `monitoring`) mở toang cho tất cả, chứ không phải do điều kiện thứ hai match được nó! Trong K8s NetworkPolicy, luật `- podSelector` khi viết độc lập (không đi kèm `namespaceSelector` trong cùng một phần tử danh sách) sẽ chỉ áp dụng kiểm tra Pod có nhãn đó chạy **ở nội bộ namespace của Policy đó** (ở đây là namespace `production`). Nó không có tác dụng kiểm tra Pod ở namespace khác!

---

## 🔬 Thí nghiệm 3: Fix thành AND và verify

> Bây giờ chúng ta sẽ sửa lỗi bằng cách loại bỏ dấu `-` thừa trước `podSelector`. Chỉ một ký tự thay đổi nhưng hành vi hoàn toàn khác: từ OR sang AND. Sau đó verify lại để xác nhận rogue bị chặn và prometheus vẫn thông.

**Trên `controlplane`:**

1. **Xóa policy buggy trước khi apply bản fix.**
   Không nên để hai policy cùng tên tồn tại song song — xóa sạch để tránh nhầm lẫn khi debug.
   ```bash
   kubectl delete -n production networkpolicy allow-prometheus-OR-bug
   ```

2. **Apply policy AND (correct) — không có dấu `-` trước `podSelector`.**
   So sánh YAML này với bản trước: `podSelector` không có dấu `-` dẫn đầu, nghĩa là nó là **thuộc tính của cùng một item** với `namespaceSelector`. Kubernetes diễn giải: cả hai điều kiện phải đồng thời thỏa mãn — đây là AND logic.
   ```bash
   kubectl apply -n production -f - <<'EOF'
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-prometheus-AND-correct
   spec:
     podSelector:
       matchLabels:
         app: backend
     policyTypes:
     - Ingress
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: monitoring
         podSelector:              # ← KHÔNG có dấu "-" = CÙNG ITEM = AND!
           matchLabels:
             role: prometheus
       ports:
       - protocol: TCP
         port: 9090
   EOF
   ```

3. **Verify kết quả — đây là bài test cuối cùng.**
   Chạy cả ba lệnh và quan sát: prometheus thông, rogue bị timeout. Đây là hành vi đúng theo yêu cầu của CISO.
   ```bash
   # Prometheus được vào ✅
   kubectl -n monitoring exec prometheus -- nc -zv backend-metrics.production.svc.cluster.local 9090
   # Connection succeeded!

   # Rogue bị chặn ✅
   kubectl -n monitoring exec rogue -- nc -zv -w 3 backend-metrics.production.svc.cluster.local 9090
   # (timeout) ← Đúng! Rogue không có role=prometheus
   ```
   > Kết quả timeout có thể mất 3 giây — đây là bình thường, `-w 3` đặt timeout 3 giây.

---

## 🔬 Thí nghiệm 4: Verify namespace labels

> Thí nghiệm này chứng minh tại sao bước label namespace ở đầu bài là bắt buộc. Chúng ta sẽ cố tình xóa label rồi quan sát policy tự động "vô hiệu hóa" — ngay cả khi policy YAML vẫn còn đó. Sau đó restore để trạng thái trở về bình thường.

**Trên `controlplane`:**

1. **Xem labels hiện tại của namespace `monitoring`.**
   Đây là lệnh nên chạy đầu tiên mỗi khi debug NetworkPolicy không hoạt động — kiểm tra label namespace trước.
   ```bash
   kubectl get namespace monitoring --show-labels
   # NAME        LABELS
   # monitoring  name=monitoring   ← OK
   ```

2. **Xóa label và quan sát policy bị vô hiệu hóa.**
   Policy vẫn tồn tại trong cluster, nhưng `namespaceSelector` không còn tìm thấy namespace nào match — nên prometheus cũng bị chặn luôn.
   ```bash
   kubectl label namespace monitoring name-
   # Label bị xóa

   kubectl -n monitoring exec prometheus -- nc -zv -w 3 backend-metrics.production.svc.cluster.local 9090
   # (timeout) ← Policy không match nữa! namespaceSelector không có label để match
   ```
   > Đây là một trong những nguyên nhân phổ biến nhất khiến NetworkPolicy "bỗng nhiên không hoạt động" trên môi trường thực tế — ai đó vô tình xóa hoặc đổi label namespace.

3. **Restore label và xác nhận policy hoạt động lại.**
   Chỉ cần thêm lại đúng label là policy tự động kích hoạt — không cần chỉnh sửa hay apply lại YAML.
   ```bash
   kubectl label namespace monitoring name=monitoring
   kubectl -n monitoring exec prometheus -- nc -zv backend-metrics.production.svc.cluster.local 9090
   # Connection succeeded! ✅ Label restore → policy hoạt động lại
   ```

---

## 🧹 Dọn dẹp

> Sau khi hoàn thành lab, dọn sạch tài nguyên để tránh ảnh hưởng đến các bài lab tiếp theo.

```bash
kubectl -n production delete networkpolicy --all
kubectl -n production delete pod backend service/backend-metrics 2>/dev/null || true
kubectl -n monitoring delete pod prometheus rogue 2>/dev/null || true
```

---

## ✅ Tổng kết

1. **AND vs OR phụ thuộc vào dấu `-`:** Cùng `from` item (không có dấu `-` riêng) = AND. Dấu `-` riêng = item mới = OR.
2. **Hậu quả:** OR cho phép rogue pod trong namespace đúng nhưng không có label đúng vào được — security hole không visible qua `kubectl get networkpolicy`.
3. **Namespace labels là bắt buộc:** `namespaceSelector` không thể match namespace không có label tương ứng.
4. **Cách check nhanh:** `kubectl get namespace --show-labels` để verify labels trước khi debug policy.
