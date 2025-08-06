<link rel="stylesheet" href="markdown-style.css">

# 🏭 Bare Metal K3s Deployment за Odoo 18

<div align="center">

![Bare Metal Deployment](https://img.shields.io/badge/Deployment-Bare--Metal-red?style=for-the-badge&logo=kubernetes)
![Performance](https://img.shields.io/badge/Performance-Maximum-gold?style=for-the-badge&logo=speedtest)
![Network](https://img.shields.io/badge/Network-10GbE--Bonded-blue?style=for-the-badge&logo=ethernet)

**Високопроизводително bare metal K3s разгръщане с Network Bonding и Enterprise Security**

[🚀 Quick Start](#-quick-start) • [🔧 Network Bonding](#-network-bonding-configuration) • [📊 Performance](#-performance-monitoring) • [🏢 Deploy Odoo](#-odoo-18-integration)

</div>

---

## 🌟 **Ключови особености**

### 🐳 **Production-Ready K3s Архитектура**

| Component | Technology | Benefits |
|-----------|------------|----------|
| **🎛️ Portainer** | Kubernetes Management | Централизирано cluster управление |
| **🌐 Traefik Ingress** | Production-ready | SSL termination, load balancing |
| **⚖️ MetalLB** | LoadBalancer | External service access |
| **🔒 CrowdSec** | AI Security | Threat detection & prevention |

### 🌐 **Enterprise Network Bonding**

- **⚡ LACP 802.3ad** - 10GbE агрегация за максимална пропускливост
- **🔄 Active-Backup** - 1GbE failover за external connectivity
- **📈 Jumbo Frames** - 9000 bytes MTU за оптимална производителност
- **🏎️ BBR TCP** - Google's congestion control за максимален throughput
- **🎯 Dedicated Inter-Cluster** - Изолиран high-speed трафик

### 🔒 **Enterprise Security Stack**

- **🤖 AI-Powered Detection** - CrowdSec machine learning
- **🔐 Secure Remote Access** - WireGuard VPN интеграция
- **🛡️ Network Policies** - Kubernetes micro-segmentation
- **🔑 Automated SSL** - Let's Encrypt integration

---

## 🏗️ **Bare Metal Архитектура**
```

┌─────────────────────────────────────────────────────────────┐
│                    Internet/WAN Gateway                     │
│                  (192.168.1.1)                            │
└─────────────────┬───────────────────────────────────────────┘
                  │
        External LoadBalancer IPs
          (192.168.1.100-110)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│                 Master Node (192.168.1.10)                 │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐ │
│ │ K3s Master  │ │   MetalLB   │ │      Portainer          │ │
│ │ + Traefik   │ │LoadBalancer │ │   (Primary Manager)     │ │
│ └─────────────┘ └─────────────┘ └─────────────────────────┘ │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐ │
│ │ WireGuard   │ │  CrowdSec   │ │     Odoo 18 Ready       │ │
│ │    Pod      │ │    Pod      │ │    Infrastructure       │ │
│ └─────────────┘ └─────────────┘ └─────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │           Network Bonding Configuration                 │ │
│ │  🔗 bond0: 10GbE LACP (ens3f0+ens3f1) - Inter-cluster  │ │
│ │  🔗 bond1: 1GbE Backup (ens4f0+ens4f1) - External      │ │
│ │  📡 IPs: 192.168.1.10 (ext) + 10.0.0.10 (bond)         │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────┬───────────────────────────────────────────┘
                  │
        High-Speed LACP Bond Network
         (10.0.0.0/24 - Jumbo Frames)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│              Worker Nodes (192.168.1.11+)                  │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐ │
│ │   K3s       │ │   Odoo 18   │ │   High-Performance      │ │
│ │  Agent      │ │  Workloads  │ │  Storage & Database     │ │
│ └─────────────┘ └─────────────┘ └─────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │           Network Bonding Configuration                 │ │
│ │  🔗 bond0: 10GbE LACP (ens3f0+ens3f1) - Inter-cluster  │ │
│ │  🔗 bond1: 1GbE Backup (ens4f0+ens4f1) - External      │ │
│ │  📡 IPs: 192.168.1.11+ (ext) + 10.0.0.11+ (bond)       │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```
---

## 📋 **Hardware Requirements**

### 🖥️ **Enterprise Server Specifications**

| Component | Master Node | Worker Nodes | Production Recommendation |
|-----------|-------------|--------------|--------------------------|
| **CPU** | 8+ cores | 16+ cores | Intel Xeon/AMD EPYC |
| **Memory** | 16GB+ RAM | 32GB+ RAM | 64GB+ for large datasets |
| **Storage** | 100GB+ NVMe | 200GB+ NVMe | RAID 10 for databases |
| **Network** | 4x ports | 4x ports | 2x 10GbE + 2x 1GbE |

### 🌐 **Network Infrastructure**

<div class="alert alert-info">
<strong>🔧 Critical:</strong> Managed switch с LACP 802.3ad support е задължителен за bonding.
</div>

| Component | Specification | Notes |
|-----------|---------------|--------|
| **Managed Switch** | LACP 802.3ad support | Cisco, Juniper, or equivalent |
| **10GbE Connectivity** | Between all nodes | Direct attach cables OK |
| **Internet Gateway** | 192.168.1.1 | Standard gateway setup |
| **Static IPs** | All nodes | DHCP reservations recommended |

### 📊 **Network Planning Schema**
```
yaml
Network Architecture:
  External Network: "192.168.1.0/24"      # Internet-facing
    Master: "192.168.1.10"
    Workers: "192.168.1.11-20"
    LoadBalancer Pool: "192.168.1.100-110"
    
  Inter-Cluster Network: "10.0.0.0/24"    # High-speed bonded
    Master: "10.0.0.10"
    Workers: "10.0.0.11-20"
    MTU: 9000 (Jumbo Frames)
    
  Kubernetes Networks:
    Pod CIDR: "10.42.0.0/16"
    Service CIDR: "10.43.0.0/16"
    VPN Network: "10.100.0.0/24"
```
---

## 🚀 **Quick Start**

### **Стъпка 1: Repository Setup**
```
bash
# Clone deployment repository
git clone https://github.com/rosenvladimirov/k3s-odoo-docs.git
cd k3s-odoo-docs/barebone
chmod +x deploy-hybrid-k3s.sh
```
### **Стъпка 2: Network Interface Configuration**

<div class="alert alert-warning">
<strong>⚠️ Important:</strong> Проверете network interface имената преди deployment!
</div>
```
bash
# Check your network interfaces
ip link show

# Configure interface names if different from defaults
export BOND_SLAVES="eth2,eth3"        # Your 10GbE interfaces
export EXT_SLAVES="eth0,eth1"         # Your 1GbE interfaces
export ENABLE_BONDING="true"

# Alternative: Edit deploy-hybrid-k3s.sh directly
# BOND_SLAVES="${BOND_SLAVES:-your_10g_interfaces}"
# EXT_SLAVES="${EXT_SLAVES:-your_1g_interfaces}"
```
### **Стъпка 3: Master Node Deployment**
```
bash
# Deploy on Master Node (192.168.1.10)
sudo ./deploy-hybrid-k3s.sh

# The script will automatically:
# ✅ Configure LACP bonding (10GbE)
# ✅ Setup external bonding (1GbE failover)
# ✅ Apply network performance optimizations
# ✅ Install K3s master with bonded networking
# ✅ Deploy all production services (Portainer, Security, etc.)
# ✅ Configure LoadBalancer IP pools
```
### **Стъпка 4: Worker Nodes Deployment**
```
bash
# Copy script to worker nodes
scp deploy-hybrid-k3s.sh root@192.168.1.11:~/
scp deploy-hybrid-k3s.sh root@192.168.1.12:~/

# Deploy workers with bonding support
ssh root@192.168.1.11 'sudo ./deploy-hybrid-k3s.sh worker'
ssh root@192.168.1.12 'sudo ./deploy-hybrid-k3s.sh worker'

# Each worker deployment includes:
# ✅ Identical bonding configuration
# ✅ Optimized storage for database workloads
# ✅ High-performance K3s agent setup
# ✅ Network optimization for Odoo workloads
```
<div class="alert alert-success">
<strong>🎉 Deployment Complete!</strong> Your bare metal cluster is ready in 15-20 minutes.
</div>

---

## 🔧 **Network Bonding Configuration**

### **Bond Interface Specifications**

| Interface | Type | Mode | Slaves | MTU | Purpose |
|-----------|------|------|--------|-----|---------|
| **bond0** | 10GbE | LACP 802.3ad | ens3f0,ens3f1 | **9000** | Inter-cluster traffic |
| **bond1** | 1GbE | Active-Backup | ens4f0,ens4f1 | **1500** | External access |

### **IP Address Schema**

| Server | External IP | Bond IP | Role |
|--------|-------------|---------|------|
| **Master** | `192.168.1.10` | `10.0.0.10` | K3s control plane |
| **Worker-1** | `192.168.1.11` | `10.0.0.11` | Database workloads |
| **Worker-2** | `192.168.1.12` | `10.0.0.12` | Application workloads |
| **Worker-N** | `192.168.1.1N` | `10.0.0.1N` | Scale-out nodes |

### **Performance Optimizations**
```
yaml
Network Performance Features:
  BBR Congestion Control: "Maximum bandwidth utilization"
  Jumbo Frames: "9000 bytes on bond0 for 15-20% performance gain"
  TCP Buffer Optimization: "64MB send/receive buffers"
  LACP Fast Mode: "Sub-second link failure detection"
  Traffic Engineering: "K3s control plane via high-speed bond"
  CPU Affinity: "Network interrupts pinned to specific cores"
```
---

## 🛠️ **Service Access & Management**

### **LoadBalancer Services**

| Service | LoadBalancer IP | Web Access | Purpose |
|---------|-----------------|------------|---------|
| **🎛️ Portainer** | `192.168.1.104` | `http://portainer.k3s.local` | **Primary K3s Manager** |
| **🌐 Traefik** | `192.168.1.101` | `http://traefik.k3s.local` | Ingress dashboard |
| **🔒 CrowdSec** | `192.168.1.103` | `http://crowdsec.k3s.local` | Security monitoring |
| **📊 Dashboard** | `192.168.1.105` | `http://dashboard.k3s.local` | Cluster overview |
| **🔐 WireGuard** | `192.168.1.102` | N/A | VPN server (UDP:51820) |

### **Portainer - Primary Management Interface**

<div class="alert alert-info">
<strong>💡 Pro Tip:</strong> Portainer е най-лесният начин за управление на вашия K3s cluster!
</div>
```
bash
# Web Interfaces
Primary:  http://portainer.k3s.local
Direct:   http://192.168.1.104:9000
HTTPS:    https://portainer.k3s.local (if SSL enabled)

# First-time setup process:
1. Navigate to http://portainer.k3s.local
2. Create admin account (change default admin/admin123!)
3. Select "Kubernetes" environment
4. Start managing your cluster through web interface

# Advanced features available:
- Deploy applications via web GUI
- Monitor resource usage across nodes
- Manage secrets and configs
- View logs and troubleshoot issues
- Deploy Helm charts
```
---

## 🏢 **Odoo 18 Integration**

### **Production-Ready Odoo Features**

<div class="feature-grid">

#### 🏗️ **High Availability**
- Multi-replica PostgreSQL database cluster
- Load-balanced Odoo application instances
- Persistent storage with automatic failover

#### ⚡ **Performance Optimization**
- Database connection pooling
- Redis caching for sessions
- CDN-ready static asset serving
- Optimized for bonded network performance

#### 🔒 **Security & Compliance**
- SSL/TLS termination with automated certificates
- Network policies for micro-segmentation
- Secrets management for sensitive data
- Audit logging for compliance requirements

#### 💾 **Backup & Recovery**
- Automated daily PostgreSQL backups
- S3-compatible storage integration
- Point-in-time recovery capabilities
- Disaster recovery procedures

</div>

### **Deploy Production Odoo 18**
```
bash
# After successful K3s cluster deployment
git clone https://github.com/rosenvladimirov/odoo-18-k3s.git
cd odoo-18-k3s

# Configure for production
export ODOO_HOSTNAME="erp.company.com"
export ENABLE_SSL="true"
export APP_REPLICAS="3"
export ENABLE_MONITORING="true"

# Deploy to production
kubectl apply -k overlays/production/

# Check deployment status
kubectl get pods -n odoo
kubectl get ingress -n odoo

# Access your Odoo instance
https://erp.company.com
```
---

## 📊 **Performance Monitoring**

### **Network Performance Commands**
```
bash
# Check bond status and health
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1

# Real-time network monitoring
bmon                        # Bandwidth monitor
iftop -i bond0             # Traffic analysis on bond
ethtool -S bond0           # Detailed interface statistics

# Performance testing between nodes
iperf3 -s                  # Server mode on target
iperf3 -c 10.0.0.10 -t 30  # Client test via bond network
iperf3 -c 10.0.0.10 -P 4   # Multi-stream performance test
```
### **Cluster Health Monitoring**
```
bash
# Cluster status overview
kubectl get nodes -o wide
kubectl top nodes
kubectl get pods --all-namespaces

# Service monitoring
kubectl get svc --all-namespaces | grep LoadBalancer
kubectl get ingress --all-namespaces

# Portainer management (via CLI)
kubectl get pods -n portainer
kubectl logs -n portainer -l app=portainer -f

# Performance metrics
kubectl top pods --all-namespaces --sort-by=cpu
kubectl top pods --all-namespaces --sort-by=memory
```
### **Advanced Performance Tuning**
```
bash
# Network optimization verification
sysctl net.core.rmem_max        # Should be 67108864 (64MB)
sysctl net.core.wmem_max        # Should be 67108864 (64MB)
sysctl net.ipv4.tcp_congestion_control  # Should be bbr

# Bond performance analysis
cat /proc/net/bonding/bond0 | grep -A 5 "Currently Active Slave"
cat /proc/interrupts | grep eth

# Storage performance testing
fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite \
    --bs=4k --direct=0 --size=512M --numjobs=4 --runtime=60 --group_reporting
```
---

## 🚨 **Troubleshooting Guide**

### **Network Bonding Issues**

<div class="alert alert-warning">
<strong>⚠️ Common Issue:</strong> Bond interface not coming up properly
</div>
```
bash
# Check bond interface status
cat /proc/net/bonding/bond0 | grep "Bonding Mode"
cat /proc/net/bonding/bond0 | grep "MII Status"

# Verify slave interface status
ip link show | grep -E "(bond|ens)"
ethtool bond0

# Test connectivity via bond
ping -I bond0 10.0.0.11  # Test to worker node
traceroute -i bond0 10.0.0.11

# Network restart if needed (USE WITH CAUTION)
netplan apply
systemctl restart systemd-networkd

# Check for bond errors
dmesg | grep -i bond | tail -20
journalctl -u systemd-networkd | grep bond
```
### **Performance Troubleshooting**

<div class="alert alert-danger">
<strong>🔥 Issue:</strong> Lower than expected network performance
</div>
```
bash
# Check current bond utilization
cat /proc/net/bonding/bond0 | grep "Currently Active Slave"
iftop -i bond0

# Test maximum throughput (run on both nodes)
iperf3 -s                           # Server mode
iperf3 -c 10.0.0.10 -P 8 -t 60     # Multi-stream client test

# Check for network errors
cat /proc/net/dev | grep bond
ethtool -S bond0 | grep error

# CPU interrupt distribution
cat /proc/interrupts | grep eth
echo 2 > /proc/irq/24/smp_affinity  # Example interrupt pinning
```
### **K3s Cluster Issues**
```
bash
# Check cluster node connectivity
kubectl get nodes
kubectl describe node <node-name>

# Examine cluster networking
kubectl get pods -n kube-system
kubectl logs -n kube-system -l app=traefik

# Service troubleshooting
kubectl get endpoints --all-namespaces
kubectl describe ingress --all-namespaces

# Check MetalLB LoadBalancer
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l app=metallb

# Network policy debugging
kubectl get networkpolicies --all-namespaces
kubectl describe networkpolicy <policy-name>
```
---

## 📈 **Scaling & Optimization**

### **Horizontal Scaling Guidelines**
```
yaml
Scaling Strategy:
  Add Worker Nodes:
    - Replicate identical bonding configuration
    - Ensure consistent hardware specifications
    - Maintain network performance parity
    
  Database Scaling:
    - PostgreSQL read replicas on bond network
    - Connection pooling optimization
    - Query optimization for distributed loads
    
  Application Scaling:
    - Increase Odoo replica count
    - Configure session stickiness if needed
    - Implement horizontal pod autoscaling
    
  Storage Scaling:
    - Expand Longhorn distributed storage
    - Add high-performance NVMe drives
    - Implement storage classes by performance tier
```
### **Vertical Scaling Recommendations**

| Resource | Minimum | Recommended | High-Performance |
|----------|---------|-------------|-------------------|
| **Memory** | 32GB/node | 64GB/node | 128GB+/node |
| **CPU** | 16 cores/node | 32 cores/node | 64 cores+/node |
| **Storage** | NVMe SSD | NVMe RAID 10 | NVMe with Intel Optane |
| **Network** | Single 10GbE bond | Dual 10GbE bonds | 25GbE+ bonds |

### **Advanced Performance Configurations**
```
bash
# CPU performance tuning
echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Network buffer optimization
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf  # 128MB
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf  # 128MB
echo 'net.ipv4.tcp_rmem = 4096 65536 134217728' >> /etc/sysctl.conf
sysctl -p

# Storage optimization for databases
echo mq-deadline > /sys/block/nvme0n1/queue/scheduler
echo 4096 > /sys/block/nvme0n1/queue/read_ahead_kb

# Container runtime optimization
echo 'KUBELET_EXTRA_ARGS="--max-pods=250 --kube-reserved=cpu=1,memory=2Gi"' >> /etc/default/k3s
```
---

## 🔒 **Security Hardening**

### **Enterprise Security Stack Configuration**
```
yaml
Security Components:
  CrowdSec:
    - Host log monitoring: /var/log, /var/log/k3s
    - Collections: Linux, SSH, Nginx, Traefik
    - Real-time threat analysis and blocking
    - Community threat intelligence integration
    
  WireGuard VPN:
    - Host network mode for performance
    - Client certificate management
    - Split-tunnel configuration support
    - Mobile client compatibility
    
  Network Policies:
    - Default deny all ingress
    - Explicit allow rules for services
    - Namespace-based isolation
    - External traffic controls
```
### **Firewall Configuration**

```bash
# Minimal host firewall rules
ufw allow in on bond1 to any port 22        # SSH access
ufw allow in on bond1 to any port 80,443    # HTTP/HTTPS
ufw allow in on bond1 to any port 6443      # Kubernetes API
ufw allow in on bond1 to any port 51820/udp # WireGuard VPN
ufw allow in on bond0                        # Inter-cluster traffic
ufw default deny incoming
ufw enable

# Advanced security: Rate limiting
ufw limit ssh
ufw limit 80/tcp
ufw limit 443/tcp
```
```


---

## 🎯 **Next Steps & Advanced Features**

### 🚀 **Recommended Actions**

1. **[🔒 SSL/TLS Configuration](../SECURITY-GUIDE.md)** - Implement Let's Encrypt automation
2. **[📊 Advanced Monitoring](../MONITORING-GUIDE.md)** - Deploy Prometheus + Grafana stack
3. **[💾 Backup Strategy](../BACKUP-GUIDE.md)** - Implement automated backup solutions
4. **[⚡ Deploy Odoo 18](README-k3s-odoo-18.md)** - Full enterprise ERP deployment

### 🔗 **Related Documentation**

- **[🖥️ VM Deployment Alternative](README-VM.md)** - For development environments
- **[⚡ K3s Odoo Enterprise Platform](README-k3s-odoo-18.md)** - Complete Odoo solution
- **[🔄 Migration Between Deployments](MIGRATION-GUIDE.md)** - Switch between bare metal and VM
- **[🛠️ Advanced Troubleshooting](TROUBLESHOOTING.md)** - Comprehensive problem solving

---

## 🤝 **Enterprise Support & Services**

### **📞 Professional Services**
- **🏗️ Architecture Consulting** - Infrastructure design and optimization
- **⚙️ Implementation Services** - Hands-on deployment assistance
- **🔄 Migration Services** - Zero-downtime migration support
- **🎓 Training Programs** - Team upskilling and certification
- **🏢 Odoo Customization** - Specialized modules and integrations

### **📧 Support Contacts**
- **Technical Support**: vladimirov.rosen@gmail.com
- **Enterprise Sales**: byordanov@bl-consulting.net
- **Professional Services**: vladimirov.rosen@gmail.com
- **Community Forum**: https://github.com/rosenvladimirov/odoo-18/discussions

---

<div align="center">

**🎉 Your Bare Metal K3s Cluster is Ready!**

Maximum performance infrastructure for production Odoo 18 deployments.

[📧 Get Support](mailto:vladimirov.rosen@gmail.com) • [🐛 Report Issues](https://github.com/rosenvladimirov/odoo-18-k3s/issues) • [💬 Community](https://github.com/rosenvladimirov/odoo-18-k3s/discussions)

---

**🏭 Enterprise-Grade Bare Metal K3s Platform за Odoo 18** ⚡  
*Maximum Performance. Maximum Control. Production Ready.* 🚀

</div>