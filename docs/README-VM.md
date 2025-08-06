---
layout: default
title: "VM Ръководство" 
nav_order: 3
---

# 🚀 Odoo-18 Pure K3s VM Клъстер

Cloud-native Kubernetes клъстер за **виртуални машини** с **Portainer управление**, **Pod-базирани услуги**, **опростена мрежа** и **оптимизиран за VM производителност**.

## 🌟 Ключови особености

### 🐳 **Pure Kubernetes Архитектура**
- **Portainer** - Основен интерфейс за управление на клъстера
- **Всички услуги в подове** - WireGuard, CrowdSec, storage услуги
- **Вграден Traefik** - K3s native ingress контролер
- **MetalLB LoadBalancer** - Външен достъп до услуги
- **Минимални host услуги** - Само K3s + основна защитна стена

### 🖥️ **VM-Оптимизирана Среда**
- **Авто VM откриване** - Автоматично определяне на VM роля по IP
- **Опростена мрежа** - Без сложни bond конфигурации
- **Ресурсно ефективен** - Оптимизирани resource limits за VM среда
- **Един интерфейс настройка** - Стандартна VM мрежова конфигурация
- **VM-специфичен мониторинг** - Специализирани мониторинг инструменти

### 🔒 **Pod-базирана Сигурност**
- **CrowdSec под** - Сигурностен двигател с лог мониторинг
- **WireGuard под** - VPN сървър с hostNetwork
- **Минимална host защитна стена** - Само основни правила
- **Изолация на услуги** - Цялата сигурностна логика в контейнери

### 📊 **Модерно Управление**
- **Portainer dashboard** - Пълно Kubernetes управление
- **Уеб-базиран клъстер dashboard** - Преглед на услуги
- **LoadBalancer услуги** - Директен IP достъп
- **Cloud-native подход** - Всичко контейнеризирано

## 🏗️ VM Клъстер Архитектура
```


┌─────────────────────────────────────────────────────────────┐
│               VM Host Мрежа (192.168.122.0/24)              │
└─────────────────┬───────────────────────────────────────────┘
                  │
            LoadBalancer IP-та
          (192.168.122.100-110)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│             Master VM (192.168.122.10)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ K3s Master  │ │   MetalLB   │ │      Portainer          ││
│  │ + Traefik   │ │LoadBalancer │ │   (Основен Управител)   ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ WireGuard   │ │  CrowdSec   │ │    Dashboard Под        ││
│  │    Под      │ │    Под      │ │                         ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────┬───────────────────────────────────────────┘
                  │
            VM Мрежов Мост
          (Hypervisor мрежа)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│           Worker VM 1 (192.168.122.11)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │   K3s       │ │  Под        │ │   Ресурсно              ││
│  │  Агент      │ │ Работни     │ │  Оптимизиран            ││
│  │             │ │ Натоварвания│ │                         ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│           Worker VM 2 (192.168.122.12)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │   K3s       │ │  Под        │ │   Мащабируема           ││
│  │  Агент      │ │ Работни     │ │  Архитектура            ││
│  │             │ │ Натоварвания│ │                         ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```
## 🔧 VM Среда Настройка

### 📋 **Системни изисквания**

#### **VM Изисквания**
- **Master VM**: 2+ ядра, 4GB+ RAM, 20GB+ място
- **Worker VMs**: 2+ ядра, 2GB+ RAM, 15GB+ място  
- **Hypervisor**: VMware, VirtualBox, KVM, Hyper-V
- **Мрежа**: Bridged или Host-only мрежа
- **ОС**: Ubuntu Server 22.04 LTS

#### **Мрежова Инфраструктура**
- **VM Мрежа**: `192.168.122.0/24` (default libvirt)
- **Master VM**: `192.168.122.10`
- **Worker1 VM**: `192.168.122.11`
- **Worker2 VM**: `192.168.122.12`
- **LoadBalancer Пул**: `192.168.122.100-110`

### 🖥️ **Стъпка 1: VM Създаване и ОС Настройка**

#### **Създай Master VM**
```
bash
# VMware/VirtualBox/KVM VM създаване
# - RAM: 4GB минимум
# - CPU: 2+ ядра
# - Диск: 20GB+ място
# - Мрежа: Bridged/Host-only
# - ОС: Ubuntu Server 22.04 LTS

# ОС Инсталационна конфигурация
Hostname: k3s-master-vm
Username: root
Network IP: 192.168.122.10/24
Gateway: 192.168.122.1
DNS: 8.8.8.8, 1.1.1.1

# Пост-инсталационна настройка
apt update && apt upgrade -y
apt install -y openssh-server curl wget vim
systemctl enable ssh
```
#### **Създай Worker VM-та**
```
bash
# Worker VM 1 - Клонирай от Master или отделна инсталация
Hostname: k3s-worker1-vm
Network IP: 192.168.122.11/24

# Worker VM 2 - Клонирай от Master или отделна инсталация  
Hostname: k3s-worker2-vm
Network IP: 192.168.122.12/24

# Същата пост-инсталационна настройка
apt update && apt upgrade -y
apt install -y openssh-server curl wget vim
systemctl enable ssh
```
### 🌐 **Стъпка 2: VM Мрежова Проверка**

#### **Тествай VM Свързаност**
```
bash
# От Master VM
ping 192.168.122.11  # Worker1
ping 192.168.122.12  # Worker2
ping 8.8.8.8         # Интернет

# От Worker VM-та
ping 192.168.122.10  # Master
ping 8.8.8.8         # Интернет

# Провери интерфейс конфигурация
ip addr show
ip route show
```
### 🚀 **Стъпка 3: Deploy K3s VM Клъстер**

#### **Изтегли Deployment Скрипт**
```
bash
# На всички VM-та
wget https://raw.githubusercontent.com/rosenvladimirov/odoo-18/refs/heads/1.0/vm/deploy-hybrid-k3s.sh
chmod +x deploy-vm-k3s.sh
```
## 🚀 VM Клъстер Deployment

### 1. **Deploy Master VM**
```
bash
# На Master VM (192.168.122.10)
sudo ./deploy-vm-k3s.sh master

# Или използвай авто-откриване
sudo ./deploy-vm-k3s.sh

# Скриптът ще:
# ✅ Конфигурира VM-оптимизирана мрежа
# ✅ Инсталира K3s master с VM настройки
# ✅ Deploy MetalLB с VM IP пул
# ✅ Deploy всички pod-базирани услуги
# ✅ Настрои VM мониторинг инструменти
```
### 2. **Deploy Worker VM-та**
```
bash
# На Worker VM 1 (192.168.122.11)
sudo ./deploy-vm-k3s.sh worker

# На Worker VM 2 (192.168.122.12)
sudo ./deploy-vm-k3s.sh worker

# Скриптът ще:
# ✅ Конфигурира VM мрежа
# ✅ Присъедини K3s клъстер като worker
# ✅ Настрои VM-специфичен мониторинг
```
### 3. **Провери VM Клъстер**
```
bash
# На Master VM - провери клъстер статус
kubectl get nodes
kubectl get pods --all-namespaces
vm-network-status

# Тествай inter-VM свързаност
ping 192.168.122.11  # Worker1
ping 192.168.122.12  # Worker2

# Провери LoadBalancer услуги
kubectl get svc --all-namespaces | grep LoadBalancer
```
### 4. **Достъп до VM Клъстер Услуги**
```
bash
# Основни управленски интерфейси
http://192.168.122.104:9000      # Portainer dashboard
http://192.168.122.105           # Клъстер преглед
http://192.168.122.101:8080      # Traefik dashboard
http://192.168.122.103:8080      # CrowdSec dashboard

# VPN достъп
192.168.122.102:51820            # WireGuard VPN (UDP)
```
## 🔧 VM Конфигурация

### **VM Мрежова Схема**
| VM | IP Адрес | Роля | Ресурси |
|----|------------|------|-----------|
| Master | `192.168.122.10` | K3s control plane | 4GB RAM, 2+ CPU |
| Worker1 | `192.168.122.11` | K3s worker node | 2GB RAM, 2+ CPU |
| Worker2 | `192.168.122.12` | K3s worker node | 2GB RAM, 2+ CPU |

### **LoadBalancer IP Пул**
| Услуга | LoadBalancer IP | Порт | Цел |
|---------|-----------------|------|---------|
| Traefik | `192.168.122.101` | 80, 443, 8080 | Ingress контролер |
| WireGuard | `192.168.122.102` | 51820 (UDP) | VPN сървър |
| CrowdSec | `192.168.122.103` | 8080 | Сигурностен dashboard |
| Portainer | `192.168.122.104` | 9000, 9443, 30776 | **ОСНОВЕН УПРАВИТЕЛ** |
| Dashboard | `192.168.122.105` | 80 | Клъстер преглед |

### **VM-Оптимизирани Настройки**
- **Ресурсни лимити** - По-ниски CPU/Memory заявки
- **Storage оптимизация** - Един диск или простo допълнително място
- **Мрежова простота** - Стандартна VM мрежа
- **Мониторинг инструменти** - VM-специфични производителни инструменти

## 🔧 VM Конфигурационни Променливи

| Променлива | Default Стойност | Описание |
|----------|---------------|-------------|
| `VM_MASTER_IP` | `192.168.122.10` | Master VM IP адрес |
| `VM_WORKER1_IP` | `192.168.122.11` | Worker1 VM IP адрес |
| `VM_WORKER2_IP` | `192.168.122.12` | Worker2 VM IP адрес |
| `VM_NETWORK` | `192.168.122.0/24` | VM мрежа CIDR |
| `METALLB_IP_RANGE` | `192.168.122.100-110` | LoadBalancer IP пул |
| `CLUSTER_DOMAIN` | `k3s.local` | Базов домейн за услуги |
| `ENABLE_KUBEVIRT` | `false` | Изключи nested виртуализация |

## 🌐 VM Достъп до Услуги

| Услуга | LoadBalancer IP | URL Достъп | Описание |
|---------|-----------------|------------|-------------|
| **Portainer** | `192.168.122.104` | `http://192.168.122.104:9000` | **ОСНОВЕН УПРАВИТЕЛ** |
| **Dashboard** | `192.168.122.105` | `http://192.168.122.105` | Клъстер преглед |
| **Traefik** | `192.168.122.101` | `http://192.168.122.101:8080` | Ingress dashboard |
| **CrowdSec** | `192.168.122.103` | `http://192.168.122.103:8080` | Сигурностен dashboard |
| **WireGuard** | `192.168.122.102` | N/A (UDP 51820) | VPN сървър под |

## 🐳 Portainer VM Управление

### **VM-Оптимизиран Portainer**
- **Ресурсно ефективен** - По-ниски memory/CPU лимити за VM среда
- **Пълен клъстер контрол** - Управлявай подове, услуги, ingresses
- **VM производителен мониторинг** - CPU, memory, мрежово използване
- **Лесно приложно разгръщане** - Helm charts, compose stacks

### **Portainer Достъп**
```
bash
# Основен уеб интерфейс
http://192.168.122.104:9000

# HTTPS интерфейс  
https://192.168.122.104:9443

# Default потребителски данни
Username: admin
Password: admin123
```
### **Първоначална Portainer Настройка**
1. Отвори `http://192.168.122.104:9000`
2. Създай admin профил (default: admin/admin123)
3. Избери "Kubernetes" среда
4. Започни управление на VM клъстера

## 🛠️ VM Управленски Команди

### **VM Клъстер Статус**
```
bash
# VM-специфичен мрежов мониторинг
vm-network-status

# Провери VM клъстер възли
kubectl get nodes -o wide
kubectl top nodes

# VM ресурсо използване
htop
free -h
df -h
```
### **VM Управление на Услуги**
```
bash
# Провери всички VM услуги
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces | grep LoadBalancer

# VM-специфични service логове
kubectl logs -n portainer -l app=portainer
kubectl logs -n vpn -l app=wireguard-server
kubectl logs -n security -l app=crowdsec
```
### **VM Мрежова Диагностика**
```
bash
# Тествай VM свързаност
ping 192.168.122.10  # Master
ping 192.168.122.11  # Worker1  
ping 192.168.122.12  # Worker2

# Провери VM мрежова производителност
iperf3 -s                    # Server режим
iperf3 -c 192.168.122.10     # Тест към master

# VM мрежови статистики
cat /proc/net/dev
ss -tuln | grep -E "(6443|51820|8080|9000)"
```
## 📦 VM Компоненти

### **Master VM Услуги**
- **K3s server** - Kubernetes control plane
- **Traefik ingress** - HTTP/HTTPS routing
- **MetalLB** - LoadBalancer имплементация
- **Portainer** - Основен управленски интерфейс
- **Pod услуги** - WireGuard, CrowdSec, Dashboard

### **Worker VM Услуги**
- **K3s agent** - Kubernetes worker възли
- **Pod работни натоварвания** - Приложни контейнери
- **Storage** - Локално storage осигуряване
- **Мониторинг** - VM производителни инструменти

### **VM Мрежова Конфигурация**
- **VM Мрежа**: `192.168.122.0/24` - Основна VM комуникация
- **Pod CIDR**: `10.42.0.0/16` - Kubernetes pod мрежа
- **Service CIDR**: `10.43.0.0/16` - Kubernetes service мрежа
- **VPN Мрежа**: `10.100.0.0/24` - WireGuard клиенти

## 🚨 VM Отстраняване на проблеми

### **VM Проблеми със Свързаността**
```
bash
# Провери VM мрежова конфигурация
ip addr show
ip route show
systemctl status systemd-networkd

# Тествай VM-to-VM комуникация
ping 192.168.122.10
ping 192.168.122.11
ping 192.168.122.12

# Провери VM защитна стена
ufw status
iptables -L
```
### **VM Ресурсни Проблеми**
```
bash
# Провери VM ресурсо използване
free -h
df -h
top
iotop

# Провери VM дисково място
lsblk
mount
du -sh /var/lib/k3s-data
```
### **VM Проблеми с Услуги**
```
bash
# Провери K3s статус
systemctl status k3s
systemctl status k3s-agent
journalctl -u k3s -f

# Провери VM клъстер здраве
kubectl get nodes
kubectl get pods --all-namespaces
kubectl describe nodes
```
### **VM LoadBalancer Проблеми**
```
bash
# Провери MetalLB на VM
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l app=metallb

# Тествай LoadBalancer свързаност
curl http://192.168.122.104:9000  # Portainer
curl http://192.168.122.101:8080  # Traefik
curl http://192.168.122.105       # Dashboard
```
## 📚 VM Следващи Стъпки

### **Мащабирай VM Клъстер**
```
bash
# Добави повече worker VM-та
# Създай Worker3 VM: 192.168.122.13
sudo ./deploy-vm-k3s.sh worker

# Създай Worker4 VM: 192.168.122.14  
sudo ./deploy-vm-k3s.sh worker

# Провери разширения клъстер
kubectl get nodes
```
### **VM Производителна Оптимизация**
```
bash
# VM мрежово настройване
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p

# VM storage оптимизация
# Добави допълнителни VM дискове за persistent storage
lsblk
fdisk -l
```
### **VM Мониторинг Настройка**
```
bash
# Инсталирай VM-специфичен мониторинг
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Настрой Grafana за VM метрики
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana
```
## 🤝 Принос

1. Fork repository-то
2. Създай feature branch (`git checkout -b feature/vm-improvement`)
3. Commit промените (`git commit -m 'Add VM feature'`)
4. Push към branch (`git push origin feature/vm-improvement`)
5. Отвори Pull Request

## 📄 Лиценз

Този проект е лицензиран под MIT License - вижте [LICENSE](LICENSE) файла за детайли.

## 🙏 Благодарности

- **Rancher/K3s** - За lightweight Kubernetes
- **Portainer** - За модерно Kubernetes управление  
- **CrowdSec** - За съвместна сигурност
- **WireGuard** - За сигурен VPN протокол
- **MetalLB** - За LoadBalancer имплементация
- **VM Общности** - За виртуализационни най-добри практики

---

**Направено с ❤️ за VM-базирани cloud-native разгръщания** 🚀🖥️

## 📞 Поддръжка

За въпроси и поддръжка:
- 📧 Email: vladimirov.rosen@gmail.com
- 📱 Telegram: @odoo18_support
- 🌐 Документация: https://docs.odoo-shell.dev/odoo-18

**VM-Оптимизиран Kubernetes Клъстер** 🖥️💨