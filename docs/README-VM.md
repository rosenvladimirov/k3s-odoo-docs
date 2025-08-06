<link rel="stylesheet" href="markdown-style.css">

# 🖥️ VM-Based K3s Deployment Guide

<div align="center">

![VM Deployment](https://img.shields.io/badge/Deployment-VM--Based-blue?style=for-the-badge&logo=vmware)
![K3s Version](https://img.shields.io/badge/K3s-v1.28+-green?style=for-the-badge&logo=kubernetes)
![Platform](https://img.shields.io/badge/Platform-Multi--Cloud-orange?style=for-the-badge&logo=cloud)

**Cloud-native Kubernetes клъстер за виртуални машини с Portainer управление**

[🚀 Quick Start](#-quick-start) • [📋 Requirements](#-requirements) • [🔧 Configuration](#-detailed-configuration) • [🐳 Deploy Odoo](#-deploy-odoo-18)

</div>

---

## 🌟 **Ключови особености**

### 🐳 **Pure Kubernetes Архитектура**

| Component | Description | Benefits |
|-----------|-------------|----------|
| **🎛️ Portainer** | Основен интерфейс за управление | Централизирано Kubernetes управление |
| **📦 Pod Services** | WireGuard, CrowdSec в контейнери | Изолация и мащабируемост |
| **🌐 Traefik Ingress** | K3s native ingress контролер | Автоматичен SSL и routing |
| **⚖️ MetalLB** | LoadBalancer за VM среда | Външен достъп до услуги |

### 🖥️ **VM-Оптимизирана Среда**

- **🔍 Авто VM откриване** - Автоматично определяне на VM роля по IP
- **🌐 Опростена мрежа** - Без сложни bond конфигурации  
- **⚡ Ресурсно ефективен** - Оптимизирани resource limits за VM
- **🔧 Един интерфейс** - Стандартна VM мрежова конфигурация

---

## 🏗️ **VM Клъстер Архитектура**
```

┌─────────────────────────────────────────────────────────────┐
│               VM Host Мрежа (192.168.122.0/24)              │
└─────────────────┬───────────────────────────────────────────┘
                  │
            LoadBalancer IPs
          (192.168.122.100-110)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│             Master VM (192.168.122.10)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ K3s Master  │ │   MetalLB   │ │      Portainer          ││
│  │ + Traefik   │ │LoadBalancer │ │   (Основен Управител)   ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ WireGuard   │ │  CrowdSec   │ │    Dashboard Pod        ││
│  │    Pod      │ │    Pod      │ │                         ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────┬───────────────────────────────────────────┘
                  │
            VM Network Bridge
          (Hypervisor мрежа)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│           Worker VM 1 (192.168.122.11)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │   K3s       │ │    Pod      │ │   Resource              ││
│  │  Agent      │ │ Workloads   │ │  Optimized              ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│           Worker VM 2 (192.168.122.12)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │   K3s       │ │    Pod      │ │   Scalable              ││
│  │  Agent      │ │ Workloads   │ │  Architecture           ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```
---

## 📋 **Requirements**

### 🖥️ **VM Изисквания**

| Component | Minimum | Recommended | Description |
|-----------|---------|-------------|-------------|
| **Master VM** | 2 CPU, 4GB RAM | 4 CPU, 8GB RAM | K3s control plane |
| **Worker VMs** | 2 CPU, 2GB RAM | 4 CPU, 4GB RAM | K3s worker nodes |
| **Storage** | 20GB per VM | 50GB per VM | System + K3s data |
| **Network** | 1 Gbps | 10 Gbps | VM-to-VM communication |

### 🌐 **Поддържани Hypervisors**

- ✅ **VMware** - vSphere, Workstation, ESXi
- ✅ **VirtualBox** - Desktop virtualization  
- ✅ **KVM/QEMU** - Linux virtualization
- ✅ **Hyper-V** - Windows Server virtualization
- ✅ **Cloud VMs** - AWS, Azure, GCP instances

<div class="alert alert-info">
<strong>💡 Препоръка:</strong> Използвайте bridged networking за най-добра производителност между VM-та.
</div>

---

## 🚀 **Quick Start**

### **Стъпка 1: VM Създаване**
```
bash
# VMware/VirtualBox/KVM VM configuration
VM Specs:
- RAM: 4GB minimum (Master), 2GB minimum (Workers)
- CPU: 2+ cores per VM
- Disk: 20GB+ per VM  
- Network: Bridged/Host-only
- OS: Ubuntu Server 22.04 LTS

# Network Configuration
Master VM:  192.168.122.10/24
Worker1 VM: 192.168.122.11/24  
Worker2 VM: 192.168.122.12/24
Gateway:    192.168.122.1
DNS:        8.8.8.8, 1.1.1.1
```
### **Стъпка 2: Base OS Setup**
```
bash
# На всички VM-та
apt update && apt upgrade -y
apt install -y openssh-server curl wget vim htop
systemctl enable ssh

# Test VM connectivity
ping 192.168.122.10  # Master
ping 192.168.122.11  # Worker1
ping 192.168.122.12  # Worker2
```
### **Стъпка 3: Deploy K3s Cluster**
```
bash
# Download deployment script
wget https://raw.githubusercontent.com/rosenvladimirov/odoo-18/refs/heads/1.0/vm/deploy-vm-k3s.sh
chmod +x deploy-vm-k3s.sh

# Deploy Master VM (192.168.122.10)
sudo ./deploy-vm-k3s.sh master

# Deploy Worker VMs (192.168.122.11, 192.168.122.12)
sudo ./deploy-vm-k3s.sh worker
```
<div class="alert alert-success">
<strong>✅ Deployment готов за 10-15 минути!</strong> Всички услуги се разгръщат автоматично.
</div>

---

## 🌐 **Service Access**

### **LoadBalancer Services**

| Service | LoadBalancer IP | URL Access | Description |
|---------|-----------------|------------|-------------|
| **🎛️ Portainer** | `192.168.122.104` | `http://192.168.122.104:9000` | **ОСНОВЕН УПРАВИТЕЛ** |
| **📊 Dashboard** | `192.168.122.105` | `http://192.168.122.105` | Клъстер преглед |
| **🌐 Traefik** | `192.168.122.101` | `http://192.168.122.101:8080` | Ingress dashboard |
| **🔒 CrowdSec** | `192.168.122.103` | `http://192.168.122.103:8080` | Security dashboard |
| **🔐 WireGuard** | `192.168.122.102` | UDP port 51820 | VPN server |

### **Portainer Initial Setup**
```
bash
# Access Portainer web interface
http://192.168.122.104:9000

# Default credentials (change immediately!)
Username: admin
Password: admin123

# Setup steps:
1. Open Portainer URL
2. Create admin account
3. Select "Kubernetes" environment  
4. Start managing your VM cluster
```
<div class="alert alert-warning">
<strong>⚠️ Security:</strong> Сменете default паролите преди production използване!
</div>

---

## 🔧 **Detailed Configuration**

### **VM Network Schema**
```
yaml
VM Network Configuration:
  Network: "192.168.122.0/24"
  Master: "192.168.122.10"
  Workers: 
    - "192.168.122.11"  
    - "192.168.122.12"
  LoadBalancer Pool: "192.168.122.100-110"
  
Kubernetes Networks:
  Pod CIDR: "10.42.0.0/16"
  Service CIDR: "10.43.0.0/16"
  VPN Network: "10.100.0.0/24"
```
### **Environment Variables**
```
bash
# VM Configuration
export VM_MASTER_IP="192.168.122.10"
export VM_WORKER1_IP="192.168.122.11"  
export VM_WORKER2_IP="192.168.122.12"
export VM_NETWORK="192.168.122.0/24"

# LoadBalancer Configuration
export METALLB_IP_RANGE="192.168.122.100-110"
export CLUSTER_DOMAIN="k3s.local"

# Optional Features
export ENABLE_KUBEVIRT="false"  # Disable nested virtualization
export ENABLE_MONITORING="true"
```
---

## 🐳 **Deploy Odoo 18**

### **Quick Odoo Deployment**
```
bash
# Create Odoo namespace
kubectl create namespace odoo

# Deploy Odoo with PostgreSQL
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: odoo-18
  namespace: odoo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: odoo
  template:
    metadata:
      labels:
        app: odoo
    spec:
      containers:
      - name: odoo
        image: odoo:18.0
        ports:
        - containerPort: 8069
        env:
        - name: HOST
          value: "postgres"
        - name: USER
          value: "odoo"
        - name: PASSWORD
          value: "odoo"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: odoo-service
  namespace: odoo
spec:
  type: LoadBalancer
  ports:
  - port: 8069
    targetPort: 8069
  selector:
    app: odoo
EOF
```
### **Access Odoo**
```
bash
# Check Odoo deployment
kubectl get pods -n odoo
kubectl get svc -n odoo

# Get LoadBalancer IP
kubectl get svc odoo-service -n odoo

# Access Odoo (typically on 192.168.122.106)
http://ODOO_LOADBALANCER_IP:8069

# Default Odoo credentials
Database: odoo
Email: admin@example.com
Password: admin
```
<div class="alert alert-success">
<strong>🎉 Odoo 18 готов!</strong> Отворете браузъра и започнете конфигурацията на ERP системата.
</div>

---

## 📊 **Monitoring & Management**

### **Cluster Health Checks**
```
bash
# Check cluster status
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl top nodes

# VM resource monitoring
htop
free -h
df -h
iotop
```
### **VM Network Diagnostics**
```
bash
# Test VM connectivity
ping 192.168.122.10  # Master
ping 192.168.122.11  # Worker1
ping 192.168.122.12  # Worker2

# Network performance testing
iperf3 -s                    # Server mode
iperf3 -c 192.168.122.10     # Test to master

# Check network interfaces
ip addr show
ip route show
ss -tuln
```
### **Service Logs**
```
bash
# K3s service logs
systemctl status k3s
systemctl status k3s-agent
journalctl -u k3s -f

# Pod service logs
kubectl logs -n portainer -l app=portainer
kubectl logs -n vpn -l app=wireguard-server
kubectl logs -n security -l app=crowdsec
```
---

## 🚨 **Troubleshooting**

### **VM Connectivity Issues**

<div class="alert alert-warning">
<strong>⚠️ Issue:</strong> VMs cannot communicate<br>
<strong>💡 Solution:</strong> Check VM network configuration and hypervisor settings
</div>
```
bash
# Check VM network settings
ip addr show
ip route show
systemctl status systemd-networkd

# Test hypervisor network
ping $(ip route | grep default | awk '{print $3}')

# Check firewall rules
ufw status
iptables -L
```
### **Resource Constraints**

<div class="alert alert-danger">  
<strong>🔥 Issue:</strong> Pods stuck in Pending due to resources<br>
<strong>💡 Solution:</strong> Check VM resource allocation and limits
</div>
```
bash
# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Check resource constraints
kubectl describe nodes
kubectl get pods -o wide --all-namespaces

# Adjust VM resources in hypervisor
# Increase RAM/CPU allocation
```
### **LoadBalancer Issues**
```
bash
# Check MetalLB status
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l app=metallb

# Verify IP pool configuration
kubectl get configmap -n metallb-system config -o yaml

# Test LoadBalancer connectivity
curl http://192.168.122.104:9000  # Portainer
curl http://192.168.122.101:8080  # Traefik
```
---

## 🛠️ **Advanced Configuration**

### **Scale VM Cluster**
```
bash
# Add more Worker VMs
# Create Worker3 VM: 192.168.122.13
# Create Worker4 VM: 192.168.122.14

# Deploy additional workers
sudo ./deploy-vm-k3s.sh worker

# Verify expanded cluster
kubectl get nodes
```
### **Performance Optimization**
```
bash
# VM network optimization
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p

# VM storage optimization
# Add additional VM disks for persistent storage
lsblk
fdisk -l
```
### **Monitoring Setup**
```
bash
# Deploy Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Install Prometheus monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# Install Grafana for metrics visualization
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana
```
---

## 📚 **Next Steps**

### 🎯 **Recommended Actions**

1. **[🔒 Configure SSL/TLS](../SECURITY-GUIDE.md)**
2. **[📊 Setup Advanced Monitoring](../MONITORING-GUIDE.md)** 
3. **[💾 Implement Backup Strategy](../BACKUP-GUIDE.md)**
4. **[🚀 Deploy Production Workloads](README-k3s-odoo-18.md)**

### 🔗 **Related Documentation**

- **[🏭 Bare Metal Deployment](README-BAREBONE.md)** - For production environments
- **[⚡ K3s Odoo Platform](README-k3s-odoo-18.md)** - Enterprise Odoo deployment  
- **[🔄 Migration Guide](MIGRATION-GUIDE.md)** - Upgrade between deployment types
- **[🛠️ Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

---

## 🤝 **Support & Contributing**

### **📞 Enterprise Support**
- **📧 Technical Support**: vladimirov.rosen@gmail.com
- **📱 Telegram**: @odoo18_support  
- **🌐 Documentation**: https://docs.odoo-shell.dev

### **🔧 Contributing**
1. Fork the repository
2. Create feature branch (`git checkout -b feature/vm-improvement`)
3. Commit changes (`git commit -m 'Add VM feature'`)
4. Push to branch (`git push origin feature/vm-improvement`)
5. Open Pull Request

---

<div align="center">

**🎉 VM Deployment Complete!**

Your K3s cluster is ready for development and production workloads.

[📧 Get Support](mailto:vladimirov.rosen@gmail.com) • [🐛 Report Issues](https://github.com/rosenvladimirov/odoo-18-k3s/issues) • [💬 Community](https://github.com/rosenvladimirov/odoo-18-k3s/discussions)

---

**Made with ❤️ for VM-based cloud-native deployments** 🚀🖥️

</div>