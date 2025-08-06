#!/bin/bash
set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

configure_vm_settings() {
    # VM Network Configuration - Simplified for virtual environment
    VM_MASTER_IP="${VM_MASTER_IP:-192.168.122.10}"
    VM_WORKER1_IP="${VM_WORKER1_IP:-192.168.122.11}"
    VM_WORKER2_IP="${VM_WORKER2_IP:-192.168.122.12}"
    VM_NETWORK="${VM_NETWORK:-192.168.122.0/24}"
    VM_GATEWAY="${VM_GATEWAY:-192.168.122.1}"

    # Detect current VM IP
    CURRENT_IP=$(ip route get 8.8.8.8 | awk 'NR==1{print $7}')

    # Determine VM role based on IP
    case "$CURRENT_IP" in
        "$VM_MASTER_IP") VM_ROLE="master" ;;
        "$VM_WORKER1_IP") VM_ROLE="worker1" ;;
        "$VM_WORKER2_IP") VM_ROLE="worker2" ;;
        *) VM_ROLE="auto-detect" ;;
    esac

    log_info "VM Role detected: $VM_ROLE (IP: $CURRENT_IP)"

    # K3s Configuration
    K3S_TOKEN="odoo-18-k3s-vm-cluster-2025"
    K3S_DATA_DIR="/var/lib/k3s-data"
    K3S_NODE_IP="$CURRENT_IP"
    CLUSTER_CIDR="10.42.0.0/16"
    SERVICE_CIDR="10.43.0.0/16"

    # MetalLB IP Pool - VM range
    METALLB_IP_RANGE="${METALLB_IP_RANGE:-192.168.122.100-192.168.122.110}"
    TRAEFIK_LOADBALANCER_IP="192.168.122.101"
    DASHBOARD_LOADBALANCER_IP="192.168.122.105"
    WIREGUARD_LOADBALANCER_IP="192.168.122.102"
    CROWDSEC_LOADBALANCER_IP="192.168.122.103"
    PORTAINER_LOADBALANCER_IP="192.168.122.104"

    # Storage Configuration
    LONGHORN_DIR="${LONGHORN_DIR:-/var/lib/longhorn}"
    CLUSTER_LOGS_DIR="/var/log/cluster"

    # Version Configuration
    METALLB_VERSION="${METALLB_VERSION:-v0.14.8}"
    WIREGUARD_VERSION="${WIREGUARD_VERSION:-v1.0.20230223}"
    CROWDSEC_VERSION="${CROWDSEC_VERSION:-v1.6.0}"
    PORTAINER_VERSION="${PORTAINER_VERSION:-2.21.4}"

    # SSL/TLS Configuration
    PUBLIC_IP="$CURRENT_IP"
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${PUBLIC_IP//./-}.nip.io}"
    CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-k3s.local}"

    # DNS Configuration
    DNS_SERVER="${DNS_SERVER:-8.8.8.8}"
    FALLBACK_DNS="${FALLBACK_DNS:-1.1.1.1}"

    # Admin Configuration
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${CLUSTER_DOMAIN}}"

    # Feature Flags for VM environment
    ENABLE_WIREGUARD="${ENABLE_WIREGUARD:-true}"
    ENABLE_KUBEVIRT="${ENABLE_KUBEVIRT:-false}"  # Disabled for nested VMs
    ENABLE_CROWDSEC="${ENABLE_CROWDSEC:-true}"
    ENABLE_PORTAINER="${ENABLE_PORTAINER:-true}"
    VM_MODE="true"

    log_info "VM системните настройки са конфигурирани"
}

setup_vm_storage() {
    log_info "Настройване на VM storage за Longhorn..."

    # Create directories
    mkdir -p "$LONGHORN_DIR"
    mkdir -p "$CLUSTER_LOGS_DIR"

    # Check for additional virtual disks
    log_info "Търсене на допълнителни виртуални дискове..."
    lsblk -f

    # Look for unpartitioned disks (common in VM environments)
    ADDITIONAL_DISKS=$(lsblk -rno NAME,SIZE,TYPE,MOUNTPOINT | awk '$3=="disk" && $4=="" && $1!~/^(sr|loop)/ {
        size = $2;
        if (size ~ /G$/) {
            gsub(/G/, "", size);
            if (size >= 5) print "/dev/" $1
        }
    }')

    if [[ -n "$ADDITIONAL_DISKS" ]]; then
        log_info "Намерени допълнителни виртуални дискове:"
        echo "$ADDITIONAL_DISKS"

        FIRST_DISK=$(echo "$ADDITIONAL_DISKS" | head -n1)
        log_info "Конфигуриране на storage с $FIRST_DISK..."

        # Simple ext4 partition for VM environment
        parted "$FIRST_DISK" --script mklabel gpt
        parted "$FIRST_DISK" --script mkpart primary ext4 0% 100%
        mkfs.ext4 "${FIRST_DISK}1" -F

        # Mount configuration
        echo "${FIRST_DISK}1 $LONGHORN_DIR ext4 defaults 0 2" >> /etc/fstab
        mount -a

        log_info "✅ VM storage configured at $LONGHORN_DIR"
        df -h "$LONGHORN_DIR"
    else
        log_warn "Няма допълнителни дискове - използваме root filesystem"
        chown root:root "$LONGHORN_DIR"
        chmod 755 "$LONGHORN_DIR"
    fi

    # Setup cluster logs
    mkdir -p "$CLUSTER_LOGS_DIR"
    chmod 755 "$CLUSTER_LOGS_DIR"

    log_info "✅ VM storage configuration complete"
}

setup_vm_networking() {
    log_info "Настройване на VM networking..."

    # Install basic networking tools
    apt-get update
    apt-get install -y ufw iptables-persistent bridge-utils

    # Configure simple firewall for VM environment
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp comment 'SSH'

    # Allow HTTP/HTTPS for LoadBalancer services
    ufw allow 80/tcp comment 'HTTP LoadBalancer'
    ufw allow 443/tcp comment 'HTTPS LoadBalancer'

    # Allow Kubernetes API
    ufw allow 6443/tcp comment 'Kubernetes API'

    # Allow WireGuard
    ufw allow 51820/udp comment 'WireGuard VPN'

    # Allow VM network communication
    ufw allow from "$VM_NETWORK" comment 'VM network'
    ufw allow from "$CLUSTER_CIDR" comment 'Pod network'
    ufw allow from "$SERVICE_CIDR" comment 'Service network'

    # Enable UFW
    ufw --force enable

    # Configure VM network optimization
    cat >> /etc/sysctl.conf << EOF

# VM Network Optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 1000

# TCP optimization for VMs
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1

# Enable IP forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Container networking
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    sysctl -p

    log_info "✅ VM networking configured"
}

install_vm_packages() {
    log_info "Инсталиране на VM пакети..."

    apt-get update
    apt-get install -y \
        curl wget git vim \
        htop iotop nethogs iftop \
        nfs-common open-iscsi \
        jq yq-go \
        unzip zip \
        ca-certificates gnupg lsb-release \
        software-properties-common \
        apt-transport-https \
        iperf3 netperf \
        tcpdump

    # VM monitoring tools
    apt-get install -y \
        nload bmon \
        speedtest-cli \
        mtr-tiny

    # Create VM network monitoring script
    cat > /usr/local/bin/vm-network-status << 'EOF'
#!/bin/bash
echo "=== VM Network Status ==="
echo "VM IP: $(ip route get 8.8.8.8 | awk 'NR==1{print $7}')"
echo "Interface Statistics:"
cat /proc/net/dev | grep -E "(eth|ens)" | head -5
echo ""
echo "Network Connections:"
ss -tuln | grep -E "(6443|51820|8080|9000)"
echo ""
echo "VM Cluster Connectivity:"
ping -c 1 192.168.122.10 &>/dev/null && echo "Master VM: OK" || echo "Master VM: FAIL"
ping -c 1 192.168.122.11 &>/dev/null && echo "Worker1 VM: OK" || echo "Worker1 VM: FAIL"
ping -c 1 192.168.122.12 &>/dev/null && echo "Worker2 VM: OK" || echo "Worker2 VM: FAIL"
EOF

    chmod +x /usr/local/bin/vm-network-status

    log_info "✅ VM packages installed"
}

install_k3s_master() {
    log_info "Инсталиране на K3s master на VM..."

    # Install K3s server with VM-optimized settings
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
        --data-dir=$K3S_DATA_DIR \
        --node-ip=$K3S_NODE_IP \
        --bind-address=$K3S_NODE_IP \
        --advertise-address=$K3S_NODE_IP \
        --cluster-cidr=$CLUSTER_CIDR \
        --service-cidr=$SERVICE_CIDR \
        --disable=traefik \
        --disable=servicelb \
        --write-kubeconfig-mode=644 \
        --token=$K3S_TOKEN" sh -

    # Wait for K3s to be ready
    sleep 30

    # Verify K3s installation
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    kubectl wait --for=condition=Ready nodes --all --timeout=300s

    # Install Traefik manually for better control
    log_info "Installing Traefik ingress controller..."
    kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
    kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml

    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: kube-system
  name: traefik-ingress-controller
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: kube-system
  name: traefik
  labels:
    app: traefik
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik-ingress-controller
      containers:
      - name: traefik
        image: traefik:v2.10
        args:
        - --api.insecure=true
        - --accesslog
        - --entrypoints.web.Address=:80
        - --entrypoints.websecure.Address=:443
        - --providers.kubernetescrd
        - --certificatesresolvers.default.acme.tlschallenge
        - --certificatesresolvers.default.acme.email=$LETSENCRYPT_EMAIL
        - --certificatesresolvers.default.acme.storage=acme.json
        ports:
        - name: web
          containerPort: 80
        - name: websecure
          containerPort: 443
        - name: admin
          containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  name: traefik
spec:
  type: LoadBalancer
  loadBalancerIP: $TRAEFIK_LOADBALANCER_IP
  ports:
  - port: 80
    name: web
    targetPort: 80
  - port: 443
    name: websecure
    targetPort: 443
  - port: 8080
    name: admin
    targetPort: 8080
  selector:
    app: traefik
EOF

    log_info "✅ K3s master installed на VM $K3S_NODE_IP"
}

install_k3s_worker() {
    log_info "Инсталиране на K3s worker на VM..."

    # Install K3s agent
    curl -sfL https://get.k3s.io | K3S_URL="https://$VM_MASTER_IP:6443" \
        K3S_TOKEN="$K3S_TOKEN" \
        INSTALL_K3S_EXEC="agent \
        --data-dir=$K3S_DATA_DIR \
        --node-ip=$K3S_NODE_IP" sh -

    log_info "✅ K3s worker installed на VM $K3S_NODE_IP"
}

install_metallb() {
    log_info "Инсталиране на MetalLB LoadBalancer $METALLB_VERSION..."

    # Install MetalLB
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml

    # Wait for MetalLB pods
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=300s

    # Configure IP pool for VM environment
    cat << EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: vm-pool
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: vm-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - vm-pool
EOF

    log_info "✅ MetalLB $METALLB_VERSION configured с VM IP pool $METALLB_IP_RANGE"
}

deploy_portainer() {
    if [[ "$ENABLE_PORTAINER" != "true" ]]; then
        log_warn "Portainer е disabled - прескачаме"
        return
    fi

    log_info "Deploying Portainer $PORTAINER_VERSION на VM..."

    # Create namespace
    kubectl create namespace portainer --dry-run=client -o yaml | kubectl apply -f -

    # Deploy Portainer
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: portainer-sa-clusteradmin
  namespace: portainer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: portainer-crb-clusteradmin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: portainer-sa-clusteradmin
  namespace: portainer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: portainer-data
  namespace: portainer
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: portainer
  namespace: portainer
  labels:
    app: portainer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: portainer
  template:
    metadata:
      labels:
        app: portainer
    spec:
      serviceAccountName: portainer-sa-clusteradmin
      containers:
      - name: portainer
        image: portainer/portainer-ce:$PORTAINER_VERSION
        args:
        - --admin-password-file=/data/admin-password
        - --kubernetes-cluster-endpoint=https://kubernetes.default.svc
        ports:
        - containerPort: 9000
          name: http
        - containerPort: 9443
          name: https
        - containerPort: 30776
          name: edge
        volumeMounts:
        - name: data
          mountPath: /data
        - name: admin-password
          mountPath: /data/admin-password
          subPath: admin-password
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: portainer-data
      - name: admin-password
        secret:
          secretName: portainer-admin-password
---
apiVersion: v1
kind: Secret
metadata:
  name: portainer-admin-password
  namespace: portainer
type: Opaque
data:
  admin-password: $(echo -n 'admin123' | base64)
---
apiVersion: v1
kind: Service
metadata:
  name: portainer
  namespace: portainer
  labels:
    app: portainer
spec:
  type: LoadBalancer
  loadBalancerIP: $PORTAINER_LOADBALANCER_IP
  ports:
  - port: 9000
    targetPort: 9000
    name: http
  - port: 9443
    targetPort: 9443
    name: https
  - port: 30776
    targetPort: 30776
    name: edge
  selector:
    app: portainer
EOF

    log_info "✅ Portainer $PORTAINER_VERSION deployed at http://$PORTAINER_LOADBALANCER_IP:9000"
}

deploy_wireguard_pod() {
    if [[ "$ENABLE_WIREGUARD" != "true" ]]; then
        log_warn "WireGuard е disabled - прескачаме"
        return
    fi

    log_info "Deploying WireGuard VPN pod $WIREGUARD_VERSION на VM..."

    # Create namespace
    kubectl create namespace vpn --dry-run=client -o yaml | kubectl apply -f -

    # Deploy WireGuard
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: wireguard-config
  namespace: vpn
data:
  SERVERURL: "$PUBLIC_IP"
  SERVERPORT: "51820"
  PEERS: "admin,developer,mobile"
  PEERDNS: "$DNS_SERVER"
  INTERNAL_SUBNET: "10.100.0.0"
  ALLOWEDIPS: "0.0.0.0/0"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wireguard-data
  namespace: vpn
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wireguard-server
  namespace: vpn
  labels:
    app: wireguard-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wireguard-server
  template:
    metadata:
      labels:
        app: wireguard-server
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: wireguard
        image: linuxserver/wireguard:$WIREGUARD_VERSION
        envFrom:
        - configMapRef:
            name: wireguard-config
        env:
        - name: PUID
          value: "0"
        - name: PGID
          value: "0"
        - name: TZ
          value: "Europe/Sofia"
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
            - SYS_MODULE
          privileged: true
        ports:
        - containerPort: 51820
          protocol: UDP
          hostPort: 51820
        volumeMounts:
        - name: config
          mountPath: /config
        - name: modules
          mountPath: /lib/modules
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: wireguard-data
      - name: modules
        hostPath:
          path: /lib/modules
---
apiVersion: v1
kind: Service
metadata:
  name: wireguard-service
  namespace: vpn
  labels:
    app: wireguard-server
spec:
  type: LoadBalancer
  loadBalancerIP: $WIREGUARD_LOADBALANCER_IP
  ports:
  - port: 51820
    targetPort: 51820
    protocol: UDP
    name: wireguard
  selector:
    app: wireguard-server
EOF

    log_info "✅ WireGuard $WIREGUARD_VERSION deployed на $WIREGUARD_LOADBALANCER_IP:51820"
}

deploy_crowdsec_pod() {
    if [[ "$ENABLE_CROWDSEC" != "true" ]]; then
        log_warn "CrowdSec е disabled - прескачаме"
        return
    fi

    log_info "Deploying CrowdSec security pod $CROWDSEC_VERSION на VM..."

    # Create namespace
    kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -

    # Deploy CrowdSec
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: crowdsec-config
  namespace: security
data:
  acquis.yaml: |
    ---
    filenames:
      - /var/log/host/syslog
      - /var/log/host/auth.log
    labels:
      type: syslog
    ---
    filenames:
      - /var/log/k3s/k3s.log
    labels:
      type: k3s
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: crowdsec-data
  namespace: security
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crowdsec
  namespace: security
  labels:
    app: crowdsec
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crowdsec
  template:
    metadata:
      labels:
        app: crowdsec
    spec:
      containers:
      - name: crowdsec
        image: crowdsecurity/crowdsec:$CROWDSEC_VERSION
        env:
        - name: COLLECTIONS
          value: "crowdsecurity/linux crowdsecurity/ssh crowdsecurity/traefik"
        - name: GID
          value: "1000"
        ports:
        - containerPort: 8080
          name: http
        volumeMounts:
        - name: config
          mountPath: /etc/crowdsec
        - name: data
          mountPath: /var/lib/crowdsec/data
        - name: acquis-config
          mountPath: /etc/crowdsec/acquis.yaml
          subPath: acquis.yaml
        - name: host-logs
          mountPath: /var/log/host
          readOnly: true
        - name: k3s-logs
          mountPath: /var/log/k3s
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "150m"
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: crowdsec-data
      - name: data
        persistentVolumeClaim:
          claimName: crowdsec-data
      - name: acquis-config
        configMap:
          name: crowdsec-config
      - name: host-logs
        hostPath:
          path: /var/log
      - name: k3s-logs
        hostPath:
          path: /var/log
---
apiVersion: v1
kind: Service
metadata:
  name: crowdsec-service
  namespace: security
  labels:
    app: crowdsec
spec:
  type: LoadBalancer
  loadBalancerIP: $CROWDSEC_LOADBALANCER_IP
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  selector:
    app: crowdsec
EOF

    log_info "✅ CrowdSec $CROWDSEC_VERSION deployed at http://$CROWDSEC_LOADBALANCER_IP:8080"
}

deploy_cluster_dashboard() {
    log_info "Deploying simple cluster dashboard..."

    # Create namespace
    kubectl create namespace dashboard --dry-run=client -o yaml | kubectl apply -f -

    # Deploy simple HTML dashboard
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-html
  namespace: dashboard
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>odoo-18 K3s VM Cluster</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
            h1 { color: #2c3e50; text-align: center; }
            .service-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-top: 30px; }
            .service-card { background: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
            .service-card h3 { color: #34495e; margin: 0 0 10px 0; }
            .service-card a { color: #3498db; text-decoration: none; font-weight: bold; }
            .service-card a:hover { text-decoration: underline; }
            .status { margin-top: 20px; padding: 15px; background: #d5f4e6; border-radius: 5px; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 odoo-18 K3s VM Cluster</h1>
            <p style="text-align: center; color: #7f8c8d;">Cloud-native Kubernetes cluster running on Virtual Machines</p>

            <div class="service-grid">
                <div class="service-card">
                    <h3>🐳 Portainer</h3>
                    <p>Primary Cluster Manager</p>
                    <a href="http://$PORTAINER_LOADBALANCER_IP:9000" target="_blank">Open Dashboard</a>
                </div>

                <div class="service-card">
                    <h3>🔗 Traefik</h3>
                    <p>Ingress Controller</p>
                    <a href="http://$TRAEFIK_LOADBALANCER_IP:8080" target="_blank">Open Dashboard</a>
                </div>

                <div class="service-card">
                    <h3>🛡️ CrowdSec</h3>
                    <p>Security Engine</p>
                    <a href="http://$CROWDSEC_LOADBALANCER_IP:8080" target="_blank">Open Dashboard</a>
                </div>

                <div class="service-card">
                    <h3>🔒 WireGuard</h3>
                    <p>VPN Server</p>
                    <p>UDP Port: 51820</p>
                </div>
            </div>

            <div class="status">
                <h3>📊 Cluster Status</h3>
                <p><strong>Master VM:</strong> $VM_MASTER_IP</p>
                <p><strong>Worker1 VM:</strong> $VM_WORKER1_IP</p>
                <p><strong>Worker2 VM:</strong> $VM_WORKER2_IP</p>
                <p><strong>LoadBalancer Range:</strong> $METALLB_IP_RANGE</p>
            </div>
        </div>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-dashboard
  namespace: dashboard
  labels:
    app: cluster-dashboard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-dashboard
  template:
    metadata:
      labels:
        app: cluster-dashboard
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
        resources:
          requests:
            memory: "32Mi"
            cpu: "25m"
          limits:
            memory: "64Mi"
            cpu: "50m"
      volumes:
      - name: html
        configMap:
          name: dashboard-html
---
apiVersion: v1
kind: Service
metadata:
  name: cluster-dashboard
  namespace: dashboard
  labels:
    app: cluster-dashboard
spec:
  type: LoadBalancer
  loadBalancerIP: $DASHBOARD_LOADBALANCER_IP
  ports:
  - port: 80
    targetPort: 80
    name: http
  selector:
    app: cluster-dashboard
EOF

    log_info "✅ Cluster dashboard deployed at http://$DASHBOARD_LOADBALANCER_IP"
}

show_vm_cluster_info() {
    log_info "🎉 odoo-18 K3s VM Cluster deployed successfully!"
    echo ""
    echo "=== 🌐 Service Access URLs ==="
    echo "• Portainer (Primary Manager): http://$PORTAINER_LOADBALANCER_IP:9000"
    echo "• Cluster Dashboard:           http://$DASHBOARD_LOADBALANCER_IP"
    echo "• Traefik Dashboard:           http://$TRAEFIK_LOADBALANCER_IP:8080"
    echo "• CrowdSec Dashboard:          http://$CROWDSEC_LOADBALANCER_IP:8080"
    echo "• WireGuard VPN:               $WIREGUARD_LOADBALANCER_IP:51820 (UDP)"
    echo ""
    echo "=== 🖥️ VM Cluster Nodes ==="
    echo "• Master VM:  $VM_MASTER_IP"
    echo "• Worker1 VM: $VM_WORKER1_IP"
    echo "• Worker2 VM: $VM_WORKER2_IP"
    echo ""
    echo "=== 🔑 Default Credentials ==="
    echo "• Portainer: admin / admin123"
    echo ""
    echo "=== 📊 Management Commands ==="
    echo "• Check cluster status: kubectl get nodes"
    echo "• Check all services:   kubectl get svc --all-namespaces"
    echo "• VM network status:    vm-network-status"
    echo ""
    echo "Happy clustering! 🚀"
}

# Main deployment function
main() {
    log_info "🚀 Starting odoo-18 K3s VM Cluster deployment..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Configure VM settings
    configure_vm_settings

    # Setup VM environment
    install_vm_packages
    setup_vm_storage
    setup_vm_networking

    # Determine deployment mode
    case "${1:-auto}" in
        "master")
            log_info "Deploying K3s Master VM..."
            install_k3s_master
            sleep 30
            install_metallb
            deploy_portainer
            deploy_wireguard_pod
            deploy_crowdsec_pod
            deploy_cluster_dashboard
            show_vm_cluster_info
            ;;
        "worker")
            log_info "Deploying K3s Worker VM..."
            install_k3s_worker
            ;;
        "auto"|*)
            # Auto-detect based on current VM IP
            if [[ "$VM_ROLE" == "master" || "$CURRENT_IP" == "$VM_MASTER_IP" ]]; then
                log_info "Auto-detected: Master VM"
                install_k3s_master
                sleep 30
                install_metallb
                deploy_portainer
                deploy_wireguard_pod
                deploy_crowdsec_pod
                deploy_cluster_dashboard
                show_vm_cluster_info
            else
                log_info "Auto-detected: Worker VM"
                install_k3s_worker
            fi
            ;;
    esac

    log_info "✅ VM deployment complete!"
}

# Run main function
main "$@"