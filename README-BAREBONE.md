---
layout: default
title: "Ръководство за Bare Metal"
description: "Високопроизводително bare metal K3s разгръщане за Odoo 18"
nav_order: 2
---

# 🏭 Bare Metal K3s Deployment за Odoo 18

Високопроизводително **bare metal K3s разгръщане** с **Network Bonding**, **Enterprise Security** и **Production-Ready Odoo 18 ERP**.

## 🌟 Ключови Особености

### 🐳 **Production-Ready K3s Архитектура**
- **Portainer** - Централизирано управление на K3s cluster
- **Cloud-Native Services** - Всички компоненти като контейнери
- **Вграден Traefik** - Production-ready ingress controller
- **MetalLB LoadBalancer** - External service access
- **Високопроизводително networking** - Оптимизирано за Odoo workloads

### 🌐 **Enterprise Network Bonding**
- **LACP 802.3ad Bonding** - 10GbE агрегация между сървъри
- **Active-Backup External** - 1GbE резервна external свързаност
- **Jumbo Frames** - 9000 байта MTU за максимална производителност
- **Dedicated Inter-Cluster** - Отделен high-speed трафик за K3s
- **BBR Congestion Control** - TCP оптимизация

### 🔒 **Enterprise Security Stack**
- **CrowdSec** - AI-powered threat detection
- **WireGuard VPN** - Secure remote access
- **Network Policies** - Micro-segmentation
- **TLS Termination** - Automated SSL certificates

### 🏢 **Odoo 18 Ready Infrastructure**
- **High-Performance Storage** - Optimized для ERP workloads
- **Database Clustering** - PostgreSQL HA setup
- **Scalable Architecture** - От development до enterprise scale
- **Backup & Recovery** - Automated point-in-time recovery

## 🏗️ Архитектура
```

┌─────────────────────────────────────────────────────────────┐
│                    Internet/WAN                            │
└─────────────────┬───────────────────────────────────────────┘
                  │
            LoadBalancer IPs
        ┌─────────┼─────────────────┐
        │         │                 │
        │   192.168.1.101-110       │
        │                           │
┌───────▼────────────────────────────▼────────────────────────┐
│                 Master Node                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ K3s Master  │ │   MetalLB   │ │      Portainer          ││
│  │ + Traefik   │ │LoadBalancer │ │   (Main Manager)        ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ WireGuard   │ │  CrowdSec   │ │    Odoo 18 Ready        ││
│  │    Pod      │ │    Pod      │ │                         ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │      Network Bonding Configuration                      ││
│  │  bond0: 10GbE LACP (ens3f0+ens3f1) - Inter-cluster      ││
│  │  bond1: 1GbE Backup (ens4f0+ens4f1) - External          ││
│  │  IP: 192.168.1.10 (ext) + 10.0.0.10 (bond)              ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────┬───────────────────────────────────────────┘
                  │
            High-Speed Bond Network
              (10.0.0.0/24 - Jumbo Frames)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│              Worker Nodes                                   │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │   K3s       │ │   Odoo 18   │ │    High-Performance     ││
│  │  Agent      │ │  Workloads  │ │   Storage & Database    ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │      Network Bonding Configuration                      ││
│  │  bond0: 10GbE LACP (ens3f0+ens3f1) - Inter-cluster      ││
│  │  bond1: 1GbE Backup (ens4f0+ens4f1) - External          ││
│  │  IP: 192.168.1.11+ (ext) + 10.0.0.11+ (bond)            ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```
## 🔧 Системни Изисквания

### 📋 **Hardware Requirements**

#### **Master Node**
- **CPU**: 8+ cores, Intel/AMD с virtualization support
- **Memory**: 16GB+ RAM (32GB+ за production Odoo)
- **Storage**: 100GB+ NVMe SSD
- **Network**: 4x network ports (2x 10GbE + 2x 1GbE)

#### **Worker Nodes**
- **CPU**: 16+ cores за Odoo workloads
- **Memory**: 32GB+ RAM (64GB+ за enterprise deployments)
- **Storage**: 200GB+ NVMe SSD за database & storage
- **Network**: 4x network ports (2x 10GbE + 2x 1GbE)

#### **Network Infrastructure**
- **Managed Switch** с LACP 802.3ad support
- **10GbE Connectivity** между всички nodes
- **Internet Gateway** на 192.168.1.1
- **Static IP Addresses** за всички nodes

### 🌐 **Network Planning**

| Component | Network | IP Range | Purpose |
|-----------|---------|----------|---------|
| **External** | 192.168.1.0/24 | .10-.20 | External access |
| **Inter-Cluster** | 10.0.0.0/24 | .10-.20 | High-speed bond |
| **LoadBalancer** | 192.168.1.0/24 | .100-.110 | Service IPs |
| **Pod Network** | 10.42.0.0/16 | Auto | K3s pods |
| **Service Network** | 10.43.0.0/16 | Auto | K3s services |

## 🚀 Deployment Process

### 1. **Repository Setup**
```
bash
git clone https://github.com/rosenvladimirov/k3s-odoo-docs.git
cd k3s-odoo-docs/barebone
chmod +x deploy-k3s.sh
```
### 2. **Network Interface Configuration**
```
bash
# Ако имате различни network interface имена:
export BOND_SLAVES="eth2,eth3"        # За 10GbE ports
export EXT_SLAVES="eth0,eth1"         # За 1GbE ports
export ENABLE_BONDING="true"

# Или edit в deploy-k3s.sh:
# BOND_SLAVES="${BOND_SLAVES:-your_10g_interfaces}"
# EXT_SLAVES="${EXT_SLAVES:-your_1g_interfaces}"
```
### 3. **Master Node Deployment**
```
bash
# На Master Node (192.168.1.10)
sudo ./deploy-k3s.sh

# Script ще:
# ✅ Configure LACP bonding (ens3f0+ens3f1)
# ✅ Configure external bonding (ens4f0+ens4f1)  
# ✅ Setup high-performance network optimization
# ✅ Install K3s master с bond networking
# ✅ Deploy всички production services
# ✅ Setup Portainer management interface
```
### 4. **Worker Node Deployment**
```
bash
# Copy script to worker nodes
scp deploy-k3s.sh root@192.168.1.11:~/

# Deploy worker с bonding support
ssh root@192.168.1.11 './deploy-k3s.sh worker'

# Script ще:
# ✅ Configure identical bonding setup
# ✅ Setup optimized storage for Odoo
# ✅ Install K3s agent с bond communication
# ✅ Configure high-performance workload optimization
```
### 5. **Odoo 18 Deployment**
```
bash
# След успешен K3s cluster setup
git clone https://github.com/rosenvladimirov/odoo-18-k3s.git
cd odoo-18-k3s

# Deploy Odoo 18 ERP
kubectl apply -k overlays/production/

# Access Odoo
https://erp.your-domain.com
```
## 🔧 Network Bonding Configuration

### **Bond Interfaces**
| Interface | Type | Mode | Slaves | MTU | Purpose |
|-----------|------|------|--------|-----|---------|
| `bond0` | 10GbE | LACP 802.3ad | ens3f0,ens3f1 | 9000 | Inter-cluster |
| `bond1` | 1GbE | Active-Backup | ens4f0,ens4f1 | 1500 | External |

### **IP Address Schema**
| Server | External IP | Bond IP | Purpose |
|--------|-------------|---------|---------|
| Master | 192.168.1.10 | 10.0.0.10 | K3s control plane |
| Worker-1 | 192.168.1.11 | 10.0.0.11 | Odoo workloads |
| Worker-N | 192.168.1.1N | 10.0.0.1N | Scale-out nodes |

### **Performance Optimizations**
- **BBR Congestion Control** - Maximum bandwidth utilization
- **Jumbo Frames** - 9000 bytes on bond0 for performance
- **Optimized TCP Buffers** - 64MB network buffers
- **LACP Fast Mode** - Sub-second failure detection
- **Traffic Shaping** - K3s traffic via high-speed bond

## 🛠️ Management Access

| Service | LoadBalancer IP | URL | Purpose |
|---------|-----------------|-----|---------|
| **Portainer** | `192.168.1.104` | `http://portainer.k3s.local` | **Main K3s Manager** |
| **Traefik** | `192.168.1.101` | `http://traefik.k3s.local` | Ingress dashboard |
| **CrowdSec** | `192.168.1.103` | `http://crowdsec.k3s.local` | Security monitoring |
| **WireGuard** | `192.168.1.102` | N/A | VPN access (port 51820) |

### **Portainer - Primary Management Interface**
```
bash
# Web Interface
http://portainer.k3s.local
http://192.168.1.104:9000

# HTTPS Interface  
https://portainer.k3s.local
https://192.168.1.104:9443

# First-time setup
1. Access http://portainer.k3s.local
2. Create admin user (default: admin/admin123)
3. Select "Kubernetes" environment
4. Start managing cluster via web interface
```
## 🏢 Odoo 18 Integration

### **Production-Ready Features**
- **High Availability** - Multi-replica PostgreSQL database
- **Persistent Storage** - Longhorn distributed storage
- **SSL Termination** - Automated Let's Encrypt certificates
- **Load Balancing** - MetalLB external access
- **Backup & Recovery** - S3-compatible automated backups
- **Security** - Network policies & secret management

### **Performance Optimization for Odoo**
- **Dedicated Database Nodes** - PostgreSQL cluster on bond network
- **High-IOPS Storage** - NVMe SSD optimized для database workloads
- **Memory Caching** - Redis cluster для session management
- **CDN Ready** - Static asset optimization
- **Monitoring** - Comprehensive metrics & alerting

## 🔒 Security Configuration

### **Enterprise Security Stack**
```
bash
# CrowdSec Security Engine
- Host log monitoring: /var/log, /var/log/k3s
- Collections: Linux, SSH, Nginx, Traefik protection
- Real-time analysis: Log parsing & threat detection
- Network monitoring: Bond interface analysis

# WireGuard VPN Server
- hostNetwork mode: Direct access to port 51820
- VPN network: 10.100.0.0/24
- Client generation: Admin, developer, mobile
- Bond traffic: VPN communication via external bond

# Minimal Host Security
ufw allow in on bond1 to any port 22        # SSH
ufw allow in on bond1 to any port 80,443    # HTTP/HTTPS  
ufw allow in on bond1 to any port 6443      # K8s API
ufw allow in on bond1 to any port 51820/udp # WireGuard
ufw allow in on bond0                        # Inter-cluster
```
## 📊 Performance Monitoring

### **Network Performance Commands**
```
bash
# Check bond status
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1

# Monitor network performance
bmon                        # Real-time bandwidth monitoring
iftop -i bond0             # Traffic analysis
ethtool -S bond0           # Interface statistics

# Performance testing
iperf3 -s                  # Server mode
iperf3 -c 10.0.0.10 -t 30  # Client test via bond
```
### **Cluster Management Commands**
```
bash
# Check cluster status
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# Portainer management
kubectl get pods -n portainer
kubectl logs -n portainer -l app=portainer

# Service monitoring
kubectl get svc --all-namespaces | grep LoadBalancer
```
## 🚨 Troubleshooting

### **Network Bonding Issues**
```
bash
# Check bond status
cat /proc/net/bonding/bond0 | grep "Slave Interface"
cat /proc/net/bonding/bond0 | grep "MII Status"

# Test connectivity
ping 10.0.0.10  # Master bond IP
ping 10.0.0.11  # Worker bond IP

# Check interface status
ip link show bond0
ethtool bond0

# Network restart if needed
netplan apply
systemctl restart systemd-networkd
```
### **Performance Issues**
```
bash
# Check bond utilization
cat /proc/net/bonding/bond0 | grep "Currently Active Slave"
iftop -i bond0

# Test maximum throughput
iperf3 -s                    # On one server
iperf3 -c 10.0.0.10 -P 4    # Multi-stream test

# Check for errors
dmesg | grep bond
journalctl -u systemd-networkd | grep bond
```
### **K3s Cluster Issues**
```
bash
# Check cluster connectivity
kubectl get nodes
kubectl describe node <node-name>

# Service troubleshooting
kubectl get pods --all-namespaces
kubectl logs -n <namespace> <pod-name>

# Network policy debugging
kubectl get networkpolicies --all-namespaces
```
## 📈 Scaling Guidelines

### **Horizontal Scaling**
- **Add Worker Nodes**: Replicate bonding configuration
- **Database Scaling**: PostgreSQL read replicas
- **Storage Scaling**: Longhorn distributed expansion
- **Load Balancing**: MetalLB pool expansion

### **Vertical Scaling**
- **Memory**: 64GB+ за large Odoo databases
- **CPU**: 32+ cores за concurrent users
- **Storage**: NVMe RAID за database performance
- **Network**: Multiple 10GbE bonds за high throughput

---

**🏭 Enterprise-Grade Bare Metal K3s Platform за Odoo 18** ⚡

*Maximum Performance. Maximum Control. Production Ready.* 🚀