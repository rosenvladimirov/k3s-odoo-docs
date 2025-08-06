#!/bin/bash
set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

configure_system_settings() {
    # Network Configuration
    MASTER_IP="192.168.1.10"
    WORKER_HOST_IP="192.168.1.11"
    PUBLIC_IP="${PUBLIC_IP:-$MASTER_IP}"

    # High-Performance Inter-Server Network
    BOND_INTERFACE="bond0"
    BOND_IP_MASTER="10.0.0.10"
    BOND_IP_WORKER="10.0.0.11"
    BOND_NETWORK="10.0.0.0/24"
    BOND_MODE="${BOND_MODE:-802.3ad}"  # LACP aggregation
    BOND_SLAVES="${BOND_SLAVES:-ens3f0,ens3f1}"  # 10GbE ports
    BOND_MTU="${BOND_MTU:-9000}"  # Jumbo frames

    # External Network Configuration
    EXT_INTERFACE="bond1"
    EXT_SLAVES="${EXT_SLAVES:-ens4f0,ens4f1}"  # 1GbE external ports
    EXT_MTU="${EXT_MTU:-1500}"

    # MetalLB IP Pool - ИЗПОЛЗВА СЕ В install_metallb()
    METALLB_IP_RANGE="${METALLB_IP_RANGE:-192.168.1.100-192.168.1.110}"
    TRAEFIK_LOADBALANCER_IP="192.168.1.101"
    DASHBOARD_LOADBALANCER_IP="192.168.1.105"
    WIREGUARD_LOADBALANCER_IP="192.168.1.102"
    CROWDSEC_LOADBALANCER_IP="192.168.1.103"
    PORTAINER_LOADBALANCER_IP="192.168.1.104"

    # K3s Configuration - K3S_NODE_IP се използва в install_k3s_master()
    K3S_TOKEN="odoo-18-k3s-cluster-2025"
    K3S_DATA_DIR="/var/lib/k3s-data"
    K3S_NODE_IP="${BOND_IP_MASTER}"  # ИЗПОЛЗВА СЕ за node IP
    CLUSTER_CIDR="10.42.0.0/16"
    SERVICE_CIDR="10.43.0.0/16"

    # Storage Configuration - LONGHORN_DIR се използва в setup_host_lvm()
    LONGHORN_DIR="${LONGHORN_DIR:-/var/lib/longhorn}"
    CLUSTER_LOGS_DIR="/var/log/cluster"

    # Version Configuration - ИЗПОЛЗВАТ СЕ в deploy функциите
    METALLB_VERSION="${METALLB_VERSION:-v0.14.8}"
    WIREGUARD_VERSION="${WIREGUARD_VERSION:-v1.0.20230223}"
    CROWDSEC_VERSION="${CROWDSEC_VERSION:-v1.6.0}"
    PORTAINER_VERSION="${PORTAINER_VERSION:-2.21.4}"

    # SSL/TLS Configuration
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${PUBLIC_IP//./-}.nip.io}"
    CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-k3s.local}"

    # DNS Configuration
    DNS_SERVER="${DNS_SERVER:-192.168.1.100}"  # Pi-hole DNS
    FALLBACK_DNS="${FALLBACK_DNS:-8.8.8.8,1.1.1.1}"

    # Admin Configuration
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${CLUSTER_DOMAIN}}"

    # Feature Flags
    ENABLE_WIREGUARD="${ENABLE_WIREGUARD:-true}"
    ENABLE_KUBEVIRT="${ENABLE_KUBEVIRT:-true}"
    ENABLE_CROWDSEC="${ENABLE_CROWDSEC:-true}"
    ENABLE_PORTAINER="${ENABLE_PORTAINER:-true}"
    DATACENTER_MODE="${DATACENTER_MODE:-false}"
    ENABLE_BONDING="${ENABLE_BONDING:-true}"

    log_info "Системните настройки са конфигурирани"
}

setup_host_lvm() {
    log_info "Настройване на LVM storage за Longhorn..."

    # Create Longhorn directory - ИЗПОЛЗВА LONGHORN_DIR
    mkdir -p "$LONGHORN_DIR"
    mkdir -p "$CLUSTER_LOGS_DIR"

    # Detect additional storage devices
    log_info "Търсене на допълнителни storage устройства..."

    # List available block devices
    lsblk -f

    # Check for unmounted block devices larger than 10GB
    ADDITIONAL_DISKS=$(lsblk -rno NAME,SIZE,TYPE,MOUNTPOINT | awk '$3=="disk" && $4=="" && $2~/G$/ {
        size = $2; gsub(/G/, "", size);
        if (size >= 10) print "/dev/" $1
    }')

    if [[ -n "$ADDITIONAL_DISKS" ]]; then
        log_info "Намерени допълнителни дискове за LVM:"
        echo "$ADDITIONAL_DISKS"

        # Create LVM setup for first additional disk
        FIRST_DISK=$(echo "$ADDITIONAL_DISKS" | head -n1)
        log_info "Конфигуриране на LVM с $FIRST_DISK..."

        # Create LVM physical volume
        pvcreate "$FIRST_DISK" || log_warn "PV already exists или failed"

        # Create volume group
        vgcreate longhorn-vg "$FIRST_DISK" 2>/dev/null || log_warn "VG already exists"

        # Create logical volume (80% of space)
        lvcreate -l 80%FREE -n longhorn-lv longhorn-vg 2>/dev/null || log_warn "LV already exists"

        # Format with ext4
        mkfs.ext4 /dev/longhorn-vg/longhorn-lv -F 2>/dev/null || log_warn "Already formatted"

        # Mount at LONGHORN_DIR
        echo "/dev/longhorn-vg/longhorn-lv $LONGHORN_DIR ext4 defaults 0 2" >> /etc/fstab
        mount -a

        log_info "✅ LVM storage configured at $LONGHORN_DIR"
        df -h "$LONGHORN_DIR"
    else
        log_warn "Няма допълнителни дискове - използваме root filesystem"
        # Ensure directory exists with proper permissions
        chown root:root "$LONGHORN_DIR"
        chmod 755 "$LONGHORN_DIR"
    fi

    # Create cluster logs directory
    mkdir -p "$CLUSTER_LOGS_DIR"
    chmod 755 "$CLUSTER_LOGS_DIR"

    log_info "✅ Storage configuration complete"
}

install_metallb() {
    log_info "Инсталиране на MetalLB LoadBalancer $METALLB_VERSION..."

    # Install MetalLB using version variable
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml

    # Wait for MetalLB pods
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=300s

    # Configure IP pool using METALLB_IP_RANGE variable
    cat << EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

    log_info "✅ MetalLB $METALLB_VERSION configured с IP pool $METALLB_IP_RANGE"
}

deploy_portainer() {
    if [[ "$ENABLE_PORTAINER" != "true" ]]; then
        log_warn "Portainer е disabled - прескачаме"
        return
    fi

    log_info "Deploying Portainer $PORTAINER_VERSION..."

    # Create namespace
    kubectl create namespace portainer --dry-run=client -o yaml | kubectl apply -f -

    # Deploy Portainer using version variable
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
      storage: 10Gi
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
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
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

    # Create Ingress for web access
    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portainer-ingress
  namespace: portainer
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.rule: Host(\`portainer.$CLUSTER_DOMAIN\`)
spec:
  rules:
  - host: portainer.$CLUSTER_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: portainer
            port:
              number: 9000
EOF

    log_info "✅ Portainer $PORTAINER_VERSION deployed at http://portainer.$CLUSTER_DOMAIN"
    log_info "Default admin password: admin123"
}

deploy_wireguard_pod() {
    if [[ "$ENABLE_WIREGUARD" != "true" ]]; then
        log_warn "WireGuard е disabled - прескачаме"
        return
    fi

    log_info "Deploying WireGuard VPN pod $WIREGUARD_VERSION..."

    # Create namespace
    kubectl create namespace vpn --dry-run=client -o yaml | kubectl apply -f -

    # Deploy WireGuard using version variable
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
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
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

    log_info "Deploying CrowdSec security pod $CROWDSEC_VERSION..."

    # Create namespace
    kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -

    # Deploy CrowdSec using version variable
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
      - /var/log/host/kern.log
    labels:
      type: syslog
    ---
    filenames:
      - /var/log/k3s/k3s.log
    labels:
      type: k3s
    ---
    source: docker
    container_name:
      - traefik*
    labels:
      type: traefik
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
      storage: 2Gi
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
          value: "crowdsecurity/linux crowdsecurity/ssh crowdsecurity/nginx crowdsecurity/traefik"
        - name: GID
          value: "1000"
        - name: DISABLE_AGENT
          value: "false"
        - name: DISABLE_LOCAL_API
          value: "false"
        - name: LEVEL_INFO
          value: "true"
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
        - name: docker-sock
          mountPath: /var/run/docker.sock
          readOnly: true
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "300m"
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
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
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
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: crowdsec-ingress
  namespace: security
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.rule: Host(\`crowdsec.$CLUSTER_DOMAIN\`)
spec:
  rules:
  - host: crowdsec.$CLUSTER_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: crowdsec-service
            port:
              number: 8080
EOF

    log_info "✅ CrowdSec $CROWDSEC_VERSION deployed at http://crowdsec.$CLUSTER_DOMAIN"
}

# [Previous functions remain the same]
setup_network_bonding() {
    if [[ "$ENABLE_BONDING" != "true" ]]; then
        log_warn "Network bonding е disabled - използваме single interface"
        return
    fi

    log_info "Настройване на high-performance network bonding..."

    # Install bonding support
    apt-get update
    apt-get install -y ifenslave ethtool

    # Load bonding module
    modprobe bonding
    echo 'bonding' >> /etc/modules

    # Detect available network interfaces
    log_info "Detecting network interfaces..."
    ip link show | grep -E "^[0-9]+: (ens|eth|enp)" | cut -d: -f2 | tr -d ' '

    # Create bonding configuration
    log_info "Creating network bonding configuration..."

    # Backup original network config
    cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.backup 2>/dev/null || true

    # Determine node role for IP assignment
    if [[ "${1:-}" == "worker-host-kubevirt" ]]; then
        BOND_IP="$BOND_IP_WORKER"
        EXTERNAL_IP="$WORKER_HOST_IP"
        NODE_TYPE="worker"
    else
        BOND_IP="$BOND_IP_MASTER"
        EXTERNAL_IP="$MASTER_IP"
        NODE_TYPE="master"
    fi

    # Create netplan configuration for bonding
    cat > /etc/netplan/01-cluster-bonding.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    # Disable individual interfaces that will be bonded
    $(echo $BOND_SLAVES | tr ',' '\n' | while read iface; do
      echo "    $iface:"
      echo "      dhcp4: false"
      echo "      dhcp6: false"
    done)
    $(echo $EXT_SLAVES | tr ',' '\n' | while read iface; do
      echo "    $iface:"
      echo "      dhcp4: false"
      echo "      dhcp6: false"
    done)

  bonds:
    # High-performance inter-server bond (10GbE)
    $BOND_INTERFACE:
      interfaces: [$(echo $BOND_SLAVES | tr ',' ' ' | tr ' ' ',')]
      parameters:
        mode: $BOND_MODE
        lacp-rate: fast
        mii-monitor-interval: 100
        transmit-hash-policy: layer3+4
        ad-select: bandwidth
      mtu: $BOND_MTU
      addresses:
        - $BOND_IP/24
      routes:
        # Prefer bond interface for inter-cluster communication
        - to: $BOND_NETWORK
          via: $BOND_IP
          metric: 50
        # Route K3s traffic through bond
        - to: $CLUSTER_CIDR
          via: $BOND_IP
          metric: 50
        - to: $SERVICE_CIDR
          via: $BOND_IP
          metric: 50

    # External connectivity bond (1GbE)
    $EXT_INTERFACE:
      interfaces: [$(echo $EXT_SLAVES | tr ',' ' ' | tr ' ' ',')]
      parameters:
        mode: active-backup
        primary: $(echo $EXT_SLAVES | cut -d',' -f1)
        mii-monitor-interval: 100
        fail-over-mac: active
      mtu: $EXT_MTU
      dhcp4: false
      addresses:
        - $EXTERNAL_IP/24
      gateway4: 192.168.1.1
      nameservers:
        addresses: [$DNS_SERVER, $FALLBACK_DNS]
        search: [$CLUSTER_DOMAIN]
      routes:
        # Default route through external bond
        - to: 0.0.0.0/0
          via: 192.168.1.1
          metric: 100
EOF

    # Apply network configuration
    log_info "Applying network bonding configuration..."
    netplan apply

    # Wait for interfaces to come up
    sleep 10

    # Verify bonding status
    log_info "Verifying network bonding..."
    if [[ -f /proc/net/bonding/$BOND_INTERFACE ]]; then
        log_info "✅ Inter-server bond status:"
        cat /proc/net/bonding/$BOND_INTERFACE | head -20
    fi

    if [[ -f /proc/net/bonding/$EXT_INTERFACE ]]; then
        log_info "✅ External bond status:"
        cat /proc/net/bonding/$EXT_INTERFACE | head -20
    fi

    # Optimize network settings for high-performance
    log_info "Optimizing network performance settings..."
    cat >> /etc/sysctl.conf << EOF

# High-Performance Network Bonding Optimization
# Increase network buffer sizes
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600

# TCP optimization for high-bandwidth
net.ipv4.tcp_rmem = 4096 65536 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# Reduce TCP timeouts
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 10

# Enable IP forwarding for cluster
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Optimize for containers
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    sysctl -p

    # Test connectivity
    log_info "Testing inter-server connectivity..."
    if [[ "$NODE_TYPE" == "master" ]]; then
        ping -c 3 $BOND_IP_WORKER 2>/dev/null && log_info "✅ Bond connectivity to worker: OK" || log_warn "⚠️ Worker not reachable yet"
    else
        ping -c 3 $BOND_IP_MASTER 2>/dev/null && log_info "✅ Bond connectivity to master: OK" || log_warn "⚠️ Master not reachable"
    fi

    log_info "✅ High-performance network bonding configured"
    log_info "Inter-server bond: $BOND_INTERFACE ($BOND_IP)"
    log_info "External bond: $EXT_INTERFACE ($EXTERNAL_IP)"
}

setup_host_networking() {
    log_info "Настройване на advanced host networking..."

    # Setup network bonding first
    setup_network_bonding "${1:-}"

    # Configure advanced firewall с bond awareness
    apt-get update
    apt-get install -y ufw iptables-persistent

    # Reset UFW to defaults
    ufw --force reset

    # Basic rules
    ufw default deny incoming
    ufw default allow outgoing

    # SSH access на external interface
    ufw allow in on $EXT_INTERFACE to any port 22 comment 'SSH external'

    # HTTP/HTTPS за LoadBalancer services на external
    ufw allow in on $EXT_INTERFACE to any port 80 comment 'HTTP LoadBalancer'
    ufw allow in on $EXT_INTERFACE to any port 443 comment 'HTTPS LoadBalancer'

    # Kubernetes API на external
    ufw allow in on $EXT_INTERFACE to any port 6443 comment 'Kubernetes API'

    # WireGuard port на external
    ufw allow in on $EXT_INTERFACE to any port 51820/udp comment 'WireGuard VPN'

    # Inter-cluster communication на bond interface
    if [[ "$ENABLE_BONDING" == "true" ]]; then
        ufw allow in on $BOND_INTERFACE comment 'Inter-cluster bond'
        ufw allow out on $BOND_INTERFACE comment 'Inter-cluster bond out'
    fi

    # Local network access
    ufw allow from 192.168.1.0/24 comment 'Local network'
    ufw allow from $CLUSTER_CIDR comment 'Pod network'
    ufw allow from $SERVICE_CIDR comment 'Service network'
    ufw allow from $BOND_NETWORK comment 'Bond network'

    # Enable UFW
    ufw --force enable

    # Configure advanced iptables rules за bond optimization
    if [[ "$ENABLE_BONDING" == "true" ]]; then
        log_info "Configuring advanced iptables for bond optimization..."

        # Create custom chain за bond traffic
        iptables -t mangle -N BOND_OPTIMIZE 2>/dev/null || true

        # Mark inter-cluster traffic за bond routing
        iptables -t mangle -A OUTPUT -d $BOND_NETWORK -j BOND_OPTIMIZE
        iptables -t mangle -A BOND_OPTIMIZE -j MARK --set-mark 1

        # Route marked traffic през bond
        ip rule add fwmark 1 table 100 2>/dev/null || true
        ip route add default via $BOND_IP dev $BOND_INTERFACE table 100 2>/dev/null || true

        # Save iptables rules
        iptables-save > /etc/iptables/rules.v4
    fi

    log_info "✅ Advanced host networking configured"
}

install_host_packages() {
    log_info "Инсталиране на host пакети с network optimization..."
    apt-get update
    apt-get install -y \
        curl wget git vim \
        htop iotop nethogs iftop \
        lvm2 thin-provisioning-tools \
        nfs-common open-iscsi \
        jq yq-go \
        unzip zip \
        ca-certificates gnupg lsb-release \
        software-properties-common \
        apt-transport-https \
        ethtool ifenslave \
        iperf3 netperf \
        tcpdump wireshark-common

    # Network performance tools
    apt-get install -y \
        bmon nload \
        wondershaper \
        speedtest-cli \
        mtr-tiny

    # Virtualization support for KubeVirt
    if [[ "$ENABLE_KUBEVIRT" == "true" ]]; then
        apt-get install -y qemu-kvm libvirt-daemon-system virtinst cpu-checker
        # Check virtualization support
        if kvm-ok | grep -q "KVM acceleration can be used"; then
            log_info "✅ KVM virtualization support detected"
        else
            log_warn "⚠️ KVM acceleration not available - KubeVirt will use emulation"
        fi
        # Enable nested virtualization if possible
        if [[ -f /sys/module/kvm_intel/parameters/nested ]]; then
            echo 'options kvm-intel nested=1' > /etc/modprobe.d/kvm-intel.conf
            log_info "✅ Intel nested virtualization enabled"
        elif [[ -f /sys/module/kvm_amd/parameters/nested ]]; then
            echo 'options kvm-amd nested=1' > /etc/modprobe.d/kvm-amd.conf
            log_info "✅ AMD nested virtualization enabled"
        fi
    fi

    # Create network monitoring script
    cat > /usr/local/bin/cluster-network-status << 'EOF'
#!/bin/bash
echo "=== Cluster Network Status ==="
echo "Bond Interfaces:"
cat /proc/net/bonding/bond* 2>/dev/null | grep -E "(Slave Interface|MII Status|Speed|Duplex)" || echo "No bonds configured"
echo ""
echo "Interface Statistics:"
cat /proc/net/dev | grep -E "(bond|ens|eth)" | head -10
echo ""
echo "Network Connections:"
ss -tuln | grep -E "(6443|51820|8080|9000)"
echo ""
echo "Inter-cluster Connectivity:"
ping -c 1 10.0.0.10 &>/dev/null && echo "Master bond: OK" || echo "Master bond: FAIL"
ping -c 1 10.0.0.11 &>/dev/null && echo "Worker bond: OK" || echo "Worker bond: FAIL"
EOF
    chmod +x /usr/local/bin/cluster-network-status

    log_info "✅ Host packages с network tools installed"
}

install_k3s_master() {
    log_info "Инсталиране на K3s master с bond network optimization..."
    mkdir -p /etc/rancher/k3s

    # Use K3S_NODE_IP variable for K3s node IP
    K3S_NODE_IP_TO_USE="$K3S_NODE_IP"
    if [[ "$ENABLE_BONDING" != "true" ]]; then
        K3S_NODE_IP_TO_USE="$MASTER_IP"
    fi

    cat > /etc/rancher/k3s/config.yaml << EOF
cluster-init: true
token: "$K3S_TOKEN"
node-ip: "$K3S_NODE_IP_TO_USE"
node-external-ip: "$MASTER_IP"
bind-address: "$K3S_NODE_IP_TO_USE"
advertise-address: "$K3S_NODE_IP_TO_USE"
tls-san:
  - "$MASTER_IP"
  - "$PUBLIC_IP"
  - "$K3S_NODE_IP_TO_USE"
  - "$BOND_IP_MASTER"
  - "k3s-master"
write-kubeconfig-mode: "0644"
data-dir: "$K3S_DATA_DIR"
cluster-cidr: "$CLUSTER_CIDR"
service-cidr: "$SERVICE_CIDR"
# DISABLE само servicelb и local-storage - запазваме Traefik
disable:
  - "servicelb"      # Ще използваме MetalLB
  - "local-storage"  # Ще използваме Longhorn
node-label:
  - "node-role.kubernetes.io/master=true"
  - "node-type=barebone"
  - "longhorn-storage=enabled"
  - "network-type=bonded"
kubelet-arg:
  - "max-pods=250"
  - "eviction-hard=memory.available<500Mi"
  - "system-reserved=cpu=200m,memory=512Mi"
  - "node-ip=$K3S_NODE_IP_TO_USE"
# API Server за external access
kube-apiserver-arg:
  - "bind-address=$K3S_NODE_IP_TO_USE"
  - "advertise-address=$K3S_NODE_IP_TO_USE"
  - "default-not-ready-toleration-seconds=30"
  - "default-unreachable-toleration-seconds=30"
  - "audit-log-path=$CLUSTER_LOGS_DIR/k3s-audit.log"
  - "audit-log-maxage=30"
# Etcd optimization for bond network
etcd-arg:
  - "listen-client-urls=https://$K3S_NODE_IP_TO_USE:2379,https://127.0.0.1:2379"
  - "advertise-client-urls=https://$K3S_NODE_IP_TO_USE:2379"
  - "listen-peer-urls=https://$K3S_NODE_IP_TO_USE:2380"
  - "initial-advertise-peer-urls=https://$K3S_NODE_IP_TO_USE:2380"
EOF

    # Install K3s с network optimization
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s -

    # Setup kubectl
    mkdir -p /root/.kube
    cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

    # Update kubeconfig with bond IP
    sed -i "s/127.0.0.1:6443/$K3S_NODE_IP_TO_USE:6443/g" /root/.kube/config

    # Install kubectl completion
    echo 'source <(kubectl completion bash)' >> /root/.bashrc
    echo 'alias k=kubectl' >> /root/.bashrc
    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc

    # Wait for cluster
    sleep 30
    kubectl get nodes

    log_info "✅ K3s Master готов с bond network optimization!"
    log_info "API Server: https://$K3S_NODE_IP_TO_USE:6443"
}

configure_traefik() {
    log_info "Конфигуриране на built-in Traefik..."

    # Traefik LoadBalancer service
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: traefik-dashboard
  namespace: kube-system
  labels:
    app.kubernetes.io/name: traefik
spec:
  type: LoadBalancer
  loadBalancerIP: $TRAEFIK_LOADBALANCER_IP
  ports:
  - port: 8080
    targetPort: 8080
    name: dashboard
  selector:
    app.kubernetes.io/name: traefik
    app.kubernetes.io/instance: traefik
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traefik-dashboard-ingress
  namespace: kube-system
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.rule: Host(\`traefik.$CLUSTER_DOMAIN\`)
spec:
  rules:
  - host: traefik.$CLUSTER_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: traefik-dashboard
            port:
              number: 8080
EOF

    log_info "✅ Traefik configured at http://traefik.$CLUSTER_DOMAIN"
}

prepare_kubevirt() {
    if [[ "$ENABLE_KUBEVIRT" != "true" ]]; then
        log_warn "KubeVirt е disabled - прескачаме"
        return
    fi

    log_info "Preparing cluster за KubeVirt virtualization..."

    # Add KubeVirt node labels
    kubectl label nodes --all kubevirt.io/schedulable=true --overwrite

    log_info "✅ Cluster готов за KubeVirt deployment"
}

create_cluster_dashboard() {
    log_info "Създаване на cluster dashboard..."

    # Create namespace
    kubectl create namespace dashboard --dry-run=client -o yaml | kubectl apply -f -

    # Deploy simple dashboard
    cat << EOF | kubectl apply -f -
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
      - name: dashboard
        image: busybox:1.36
        command: ["/bin/sh"]
        args:
        - -c
        - |
          cat > /tmp/index.html << 'HTMLEOF'
          <!DOCTYPE html>
          <html>
          <head>
              <title>odoo-18 K3s Cluster</title>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                  body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
                  .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                  h1 { color: #2c3e50; text-align: center; margin-bottom: 30px; }
                  .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-top: 30px; }
                  .service { background: #ecf0f1; padding: 20px; border-radius: 6px; border-left: 4px solid #3498db; }
                  .service h3 { margin: 0 0 10px 0; color: #2c3e50; }
                  .service a { color: #3498db; text-decoration: none; font-weight: bold; }
                  .service a:hover { text-decoration: underline; }
                  .info { background: #e8f6f3; padding: 15px; border-radius: 6px; margin: 20px 0; }
                  .network { background: #fdf2e9; padding: 15px; border-radius: 6px; margin: 20px 0; }
              </style>
          </head>
          <body>
              <div class="container">
                  <h1>🚀 odoo-18 Pure K3s Cluster</h1>

                  <div class="info">
                      <h3>📊 Cluster Information</h3>
                      <p><strong>Master IP:</strong> $MASTER_IP</p>
                      <p><strong>Worker IP:</strong> $WORKER_HOST_IP</p>
                      <p><strong>Domain:</strong> $CLUSTER_DOMAIN</p>
                      <p><strong>Network:</strong> Pod CIDR: $CLUSTER_CIDR | Service CIDR: $SERVICE_CIDR</p>
                  </div>

                  <div class="network">
                      <h3>🌐 Network Architecture</h3>
                      <p><strong>Bond Network:</strong> $BOND_NETWORK (Inter-server)</p>
                      <p><strong>LoadBalancer Pool:</strong> $METALLB_IP_RANGE</p>
                      <p><strong>High-Speed Bond:</strong> 10GbE LACP между серверите</p>
                  </div>

                  <div class="services">
                      <div class="service">
                          <h3>🐳 Portainer</h3>
                          <p>Primary Kubernetes Manager</p>
                          <a href="http://portainer.$CLUSTER_DOMAIN" target="_blank">Open Dashboard</a><br>
                          <small>IP: $PORTAINER_LOADBALANCER_IP:9000</small>
                      </div>

                      <div class="service">
                          <h3>🌐 Traefik</h3>
                          <p>Ingress Controller Dashboard</p>
                          <a href="http://traefik.$CLUSTER_DOMAIN" target="_blank">Open Dashboard</a><br>
                          <small>IP: $TRAEFIK_LOADBALANCER_IP:8080</small>
                      </div>

                      <div class="service">
                          <h3>🔒 WireGuard VPN</h3>
                          <p>VPN Server Pod</p>
                          <p>Port: 51820 (UDP)</p>
                          <small>IP: $WIREGUARD_LOADBALANCER_IP</small>
                      </div>

                      <div class="service">
                          <h3>🛡️ CrowdSec</h3>
                          <p>Security Engine Dashboard</p>
                          <a href="http://crowdsec.$CLUSTER_DOMAIN" target="_blank">Open Dashboard</a><br>
                          <small>IP: $CROWDSEC_LOADBALANCER_IP:8080</small>
                      </div>

                      <div class="service">
                          <h3>🖥️ KubeVirt</h3>
                          <p>Virtual Machine Support</p>
                          <p>libvirt endpoint: $BOND_IP_WORKER:16509</p>
                          <small>VM Network: 192.168.100.0/24</small>
                      </div>

                      <div class="service">
                          <h3>📊 Kubernetes API</h3>
                          <p>K3s API Server</p>
                          <p>https://$K3S_NODE_IP:6443</p>
                          <small>Bond Network Optimized</small>
                      </div>
                  </div>

                  <div class="info">
                      <h3>🔧 Management Commands</h3>
                      <p><code>kubectl get nodes</code> - Check cluster nodes</p>
                      <p><code>kubectl get svc --all-namespaces</code> - List all services</p>
                      <p><code>cluster-network-status</code> - Check network bonding</p>
                  </div>
              </div>
          </body>
          </html>
          HTMLEOF

          # Start simple HTTP server
          cd /tmp && python3 -m http.server 8080
        ports:
        - containerPort: 8080
          name: http
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
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
    targetPort: 8080
    name: http
  selector:
    app: cluster-dashboard
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: dashboard
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.rule: Host(\`dashboard.$CLUSTER_DOMAIN\`)
spec:
  rules:
  - host: dashboard.$CLUSTER_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: cluster-dashboard
            port:
              number: 80
EOF

    log_info "✅ Cluster dashboard deployed at http://dashboard.$CLUSTER_DOMAIN"
}

setup_worker_host_kubevirt() {
    log_info "Настройване на Worker Host с KubeVirt + bond networking..."

    # Configure system settings for worker
    configure_system_settings

    # Setup bonding за worker host
    setup_host_networking "worker-host-kubevirt"
    install_host_packages

    # Basic networking setup
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
    sysctl -p

    # Virtualization packages за KubeVirt
    apt-get install -y \
        qemu-kvm \
        libvirt-daemon-system \
        libvirt-clients \
        virtinst \
        cpu-checker \
        bridge-utils \
        virt-manager \
        ovmf  # UEFI firmware

    # Configure libvirt за KubeVirt
    log_info "Конфигуриране на libvirt с bond network integration..."

    # Enable nested virtualization
    if [[ -f /sys/module/kvm_intel/parameters/nested ]]; then
        echo 'options kvm-intel nested=1' > /etc/modprobe.d/kvm-intel.conf
        log_info "✅ Intel nested virtualization enabled"
    elif [[ -f /sys/module/kvm_amd/parameters/nested ]]; then
        echo 'options kvm-amd nested=1' > /etc/modprobe.d/kvm-amd.conf
        log_info "✅ AMD nested virtualization enabled"
    fi

    # Configure libvirt network за KubeVirt с bond integration
    cat > /tmp/kubevirt-network.xml << EOF
<network>
  <name>kubevirt</name>
  <forward mode='nat'/>
  <bridge name='kubevirt0' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.10' end='192.168.100.250'/>
    </dhcp>
  </ip>
  <!-- Route VM traffic through bond interface -->
  <route family='ipv4' address='10.0.0.0' prefix='24' gateway='$BOND_IP_WORKER'/>
</network>
EOF

    # Define and start the network
    systemctl enable --now libvirtd
    virsh net-define /tmp/kubevirt-network.xml
    virsh net-autostart kubevirt
    virsh net-start kubevirt
    rm /tmp/kubevirt-network.xml

    # Configure libvirt group permissions
    usermod -a -G libvirt root
    usermod -a -G kvm root

    # Configure libvirt daemon
    cat > /etc/libvirt/qemu.conf << EOF
# KubeVirt Configuration
user = "root"
group = "root"
dynamic_ownership = 0

# Security settings
security_driver = "none"
security_default_confined = 0
security_require_confined = 0

# Memory settings
memory_backing_dir = "/dev/hugepages"

# Networking
clear_emulator_capabilities = 0

# Bond network optimization
migration_address = "$BOND_IP_WORKER"
migration_host = "$BOND_IP_WORKER"
EOF

    # Configure libvirt daemon options
    cat > /etc/default/libvirtd << EOF
# KubeVirt libvirtd configuration with bond networking
LIBVIRTD_ARGS="--listen --verbose"
EOF

    # Enable libvirt TCP listening за KubeVirt с bond IP
    sed -i 's/#listen_tls = 0/listen_tls = 0/' /etc/libvirt/libvirtd.conf
    sed -i 's/#listen_tcp = 1/listen_tcp = 1/' /etc/libvirt/libvirtd.conf
    sed -i 's/#tcp_port = "16509"/tcp_port = "16509"/' /etc/libvirt/libvirtd.conf
    sed -i "s/#listen_addr = \"192.168.0.1\"/listen_addr = \"$BOND_IP_WORKER\"/" /etc/libvirt/libvirtd.conf
    sed -i 's/#auth_tcp = "sasl"/auth_tcp = "none"/' /etc/libvirt/libvirtd.conf

    # Setup worker host firewall с bond awareness
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # SSH access
    ufw allow in on $EXT_INTERFACE to any port 22 comment 'SSH external'

    # K3s communication през bond
    if [[ "$ENABLE_BONDING" == "true" ]]; then
        ufw allow in on $BOND_INTERFACE comment 'K3s bond'
        ufw allow out on $BOND_INTERFACE comment 'K3s bond out'
    fi

    # Local networks
    ufw allow from 192.168.1.0/24 comment 'Local network'
    ufw allow from $CLUSTER_CIDR comment 'Pod network'
    ufw allow from $SERVICE_CIDR comment 'Service network'
    ufw allow from $BOND_NETWORK comment 'Bond network'

    # libvirt ports за KubeVirt на bond interface
    if [[ "$ENABLE_BONDING" == "true" ]]; then
        ufw allow in on $BOND_INTERFACE to any port 16509 comment 'libvirt TCP bond'
    else
        ufw allow from 192.168.1.0/24 to any port 16509 comment 'libvirt TCP'
    fi

    # Enable UFW
    ufw --force enable

    # Restart libvirt services
    systemctl restart libvirtd
    systemctl enable libvirtd

    # Check virtualization
    if kvm-ok | grep -q "KVM acceleration can be used"; then
        log_info "✅ KVM acceleration available"
    else
        log_warn "⚠️ KVM acceleration not available"
    fi

    # Install K3s agent с bond networking
    log_info "Инсталиране на K3s agent с bond networking..."
    mkdir -p /etc/rancher/k3s

    # Use bond IP for node communication
    K3S_NODE_IP_TO_USE="$BOND_IP_WORKER"
    K3S_SERVER_URL="https://$BOND_IP_MASTER:6443"

    if [[ "$ENABLE_BONDING" != "true" ]]; then
        K3S_NODE_IP_TO_USE="$WORKER_HOST_IP"
        K3S_SERVER_URL="https://$MASTER_IP:6443"
    fi

    cat > /etc/rancher/k3s/config.yaml << EOF
server: $K3S_SERVER_URL
token: $K3S_TOKEN
node-ip: $K3S_NODE_IP_TO_USE
node-external-ip: $WORKER_HOST_IP
node-label:
  - "node-role.kubernetes.io/worker=true"
  - "node-type=worker-host"
  - "kubevirt.io/schedulable=true"
  - "longhorn-storage=enabled"
  - "network-type=bonded"
kubelet-arg:
  - "max-pods=250"
  - "eviction-hard=memory.available<500Mi"
  - "system-reserved=cpu=200m,memory=512Mi"
  - "node-ip=$K3S_NODE_IP_TO_USE"
EOF

    # Install K3s agent
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" sh -

    # Wait for connection
    sleep 30

    log_info "✅ Worker Host с KubeVirt + bond networking готов!"
    log_info "Bond IP: $BOND_IP_WORKER"
    log_info "External IP: $WORKER_HOST_IP"
    log_info "libvirt endpoint: $BOND_IP_WORKER:16509"
    log_info "K3s server: $K3S_SERVER_URL"
}

show_completion_summary() {
    log_info "🎉 odoo-18 Pure K3s Cluster с Bond Networking готов!"
    echo ""
    echo "=============================================="
    echo "🚀 CLUSTER INFORMATION"
    echo "=============================================="
    echo "Master External IP: $MASTER_IP"
    echo "Worker External IP: $WORKER_HOST_IP"

    if [[ "$ENABLE_BONDING" == "true" ]]; then
        echo "Master Bond IP: $BOND_IP_MASTER"
        echo "Worker Bond IP: $BOND_IP_WORKER"
        echo "Bond Network: $BOND_NETWORK"
        echo "Bond Mode: $BOND_MODE"
        echo "Bond MTU: $BOND_MTU"
    fi

    echo "Public IP: $PUBLIC_IP"
    echo "Cluster Domain: $CLUSTER_DOMAIN"
    echo "K3s Token: $(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo 'Not available')"
    echo ""
    echo "🌐 NETWORK ARCHITECTURE"
    echo "=============================================="
    if [[ "$ENABLE_BONDING" == "true" ]]; then
        echo "Inter-server Bond: $BOND_INTERFACE ($BOND_SLAVES)"
        echo "External Bond: $EXT_INTERFACE ($EXT_SLAVES)"
        echo "Bond Speed: Up to $(echo $BOND_SLAVES | tr ',' '\n' | wc -l)x10Gbps"
        echo "External Speed: Up to $(echo $EXT_SLAVES | tr ',' '\n' | wc -l)x1Gbps"
        echo "Jumbo Frames: $BOND_MTU bytes"
        echo "K3s Communication: Via bond ($BOND_NETWORK)"
    else
        echo "Single Interface Mode: Standard networking"
    fi
    echo ""
    echo "🌐 SERVICE LOADBALANCER IPs"
    echo "=============================================="
    echo "Dashboard:    $DASHBOARD_LOADBALANCER_IP"
    echo "Portainer:    $PORTAINER_LOADBALANCER_IP (ports 9000, 9443, 30776)"
    echo "Traefik:      $TRAEFIK_LOADBALANCER_IP"
    echo "WireGuard:    $WIREGUARD_LOADBALANCER_IP:51820 (UDP)"
    echo "CrowdSec:     $CROWDSEC_LOADBALANCER_IP"
    echo "MetalLB Pool: $METALLB_IP_RANGE"
    echo ""
    echo "📦 DEPLOYED VERSIONS"
    echo "=============================================="
    echo "MetalLB:      $METALLB_VERSION"
    echo "Portainer:    $PORTAINER_VERSION"
    echo "WireGuard:    $WIREGUARD_VERSION"
    echo "CrowdSec:     $CROWDSEC_VERSION"
    echo "Longhorn Dir: $LONGHORN_DIR"
    echo ""
    echo "🔧 NETWORK MONITORING"
    echo "=============================================="
    echo "Network Status: cluster-network-status"
    echo "Bond Status: cat /proc/net/bonding/$BOND_INTERFACE"
    echo "Interface Stats: cat /proc/net/dev"
    echo "Performance Test: iperf3 -s (server) / iperf3 -c <ip> (client)"
    echo ""
    echo "🔧 WORKER HOST SETUP"
    echo "=============================================="
    echo "To add worker host с bonding:"
    echo "scp deploy-hybrid-k3s.sh root@$WORKER_HOST_IP:~/"
    echo "ssh root@$WORKER_HOST_IP './deploy-hybrid-k3s.sh worker-host-kubevirt'"
    echo ""
    if [[ "$ENABLE_BONDING" == "true" ]]; then
        echo "libvirt endpoint: $BOND_IP_WORKER:16509 (via bond)"
    else
        echo "libvirt endpoint: $WORKER_HOST_IP:16509"
    fi
    echo "libvirt network: kubevirt (192.168.100.0/24)"
    echo ""
    echo "📊 PERFORMANCE OPTIMIZATION"
    echo "=============================================="
    echo "✅ Network bonding: LACP 802.3ad"
    echo "✅ Jumbo frames: $BOND_MTU bytes"
    echo "✅ TCP BBR congestion control"
    echo "✅ Optimized network buffers"
    echo "✅ K3s traffic via high-speed bond"
    echo "✅ External traffic via redundant bond"
    echo ""
}

main() {
    case "${1:-master}" in
        "worker-host-kubevirt")
            setup_worker_host_kubevirt
            ;;
        "network-test")
            log_info "Testing inter-server network performance..."
            cluster-network-status
            ;;
        "master"|"")
            configure_system_settings
            setup_host_networking
            install_host_packages
            setup_host_lvm
            install_k3s_master
            configure_traefik
            install_metallb
            deploy_portainer
            deploy_wireguard_pod
            deploy_crowdsec_pod
            prepare_kubevirt
            create_cluster_dashboard
            show_completion_summary
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Usage: $0 [master|worker-host-kubevirt|network-test]"
            exit 1
            ;;
    esac
}

main "$@"