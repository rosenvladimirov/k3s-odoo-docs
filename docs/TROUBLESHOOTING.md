---
layout: default
title: "Отстраняване на Неизправности"
nav_order: 5
---

# 🔧 Отстраняване на Неизправности - Odoo-18 K3s Платформа

**Пълно ръководство за диагностика и решаване на проблеми в Odoo-18 K3s Platform**

## 🎯 Преглед

Това ръководство предоставя **системен подход** за диагностика и решаване на проблеми в odoo-18 K3s Platform. Покрива както **Bare Metal**, така и **ВМ сценарии** с практически решения и превантивни мерки.

---

## 📋 Категории Проблеми

### 🏗️ **Структура на Ръководството**

| Категория | Описание | Честота |
|-----------|----------|---------|
| **🚀 [Инсталация и Разгръщане](#deployment-issues)** | Проблеми при първоначално разгръщане | **Висока** |
| **🌐 [Мрежови Проблеми](#network-issues)** | Свързаност, DNS, LoadBalancer | **Висока** |
| **💾 [Проблеми със Съхранението](#storage-issues)** | Longhorn, PVC, монтиране | **Средна** |
| **🔒 [Проблеми със Сигурността](#security-issues)** | CrowdSec, WireGuard, SSL/TLS | **Средна** |
| **📊 [Проблеми с Производителността](#performance-issues)** | Ресурси, мащабиране, оптимизация | **Средна** |
| **🔧 [Проблеми с Управлението](#management-issues)** | Portainer, Dashboard, достъп | **Ниска** |
| **🖥️ [Специфични за ВМ](#vm-specific-issues)** | Виртуализация, хипервизор | **Ниска** |
| **🏭 [Специфични за Bare Metal](#barebone-specific-issues)** | Bonding, хардуер, производителност | **Ниска** |

---

## 🚀 Проблеми с Инсталацията и Разгръщането {#deployment-issues}

### ❌ **Проблем: Скриптът за Разгръщане Се Прекратява**

#### **Симптоми:**
```
bash
# Пример за грешка
bash: ./deploy-hybrid-k3s.sh: Permission denied
curl: command not found
E: Unable to locate package k3s
```
#### **Диагностика:**
```
bash
# Провери разрешенията на файла
ls -la deploy-*.sh

# Провери интернет свързаността
ping -c 3 8.8.8.8
curl -I https://get.k3s.io

# Провери наличните пакети
apt list --installed | grep curl
dpkg -l | grep wget
```
#### **Решения:**
```
bash
# 1. Поправи разрешенията
chmod +x deploy-hybrid-k3s.sh
chmod +x deploy-vm-k3s.sh

# 2. Инсталирай липсващи зависимости
sudo apt update
sudo apt install -y curl wget bash

# 3. Провери системните изисквания
free -h  # Поне 2GB RAM
df -h    # Поне 10GB свободно място
```
#### **Превенция:**
```
bash
# Създай скрипт за проверка на предварителните условия
#!/bin/bash
# pre-deployment-check.sh

echo "🔍 Проверка на системните изисквания..."

# Провери RAM
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
if [ $RAM_GB -lt 2 ]; then
    echo "❌ Недостатъчна RAM: ${RAM_GB}GB (минимум 2GB)"
    exit 1
fi

# Провери дисково пространство
DISK_GB=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
if [ $DISK_GB -lt 10 ]; then
    echo "❌ Недостатъчно дисково пространство: ${DISK_GB}GB (минимум 10GB)"
    exit 1
fi

# Провери интернет свързаността
if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "❌ Липсва интернет свързаност"
    exit 1
fi

echo "✅ Всички проверки преминаха успешно!"
```
---

### ❌ **Проблем: K3s Не Се Стартира**

#### **Симптоми:**
```
bash
Job for k3s.service failed because the control process exited with error code
FATA[0000] failed to start kubernetes API server
```
#### **Диагностика:**
```
bash
# Провери статуса на K3s услугата
sudo systemctl status k3s
sudo systemctl status k3s-agent

# Прегледай логовете
sudo journalctl -u k3s -f
sudo journalctl -u k3s-agent -f

# Провери мрежовите портове
sudo netstat -tulpn | grep :6443
sudo ss -tulpn | grep :6443

# Провери файловете за конфигурация
sudo ls -la /etc/rancher/k3s/
sudo cat /etc/rancher/k3s/k3s.yaml
```
#### **Решения:**
```
bash
# 1. Почисти предишна инсталация
sudo /usr/local/bin/k3s-uninstall.sh || true
sudo /usr/local/bin/k3s-agent-uninstall.sh || true

# 2. Почисти останали процеси
sudo pkill -f k3s

# 3. Почисти мрежовите интерфейси
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true

# 4. Рестартирай мрежовите услуги
sudo systemctl restart networking
sudo systemctl restart systemd-resolved

# 5. Преинсталирай K3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
```
---

## 🌐 Мрежови Проблеми {#network-issues}

### ❌ **Проблем: Подовете Не Могат Да Комуникират**

#### **Симптоми:**
```
bash
# Подовете в състояние на грешка
kubectl get pods --all-namespaces | grep -E "(Error|CrashLoop|Pending)"

# DNS не работи
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local
```
#### **Диагностика:**
```
bash
# Провери мрежовата конфигурация на клъстера
kubectl get nodes -o wide
kubectl describe node $(kubectl get nodes -o name | head -1 | cut -d/ -f2)

# Провери CNI плъгините
sudo ls -la /opt/cni/bin/
sudo ls -la /etc/cni/net.d/

# Провери Flannel (K3s по подразбиране)
kubectl get pods -n kube-system | grep flannel
kubectl logs -n kube-system -l app=flannel

# Провери CoreDNS
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system -l k8s-app=kube-dns
```
#### **Решения:**
```
bash
# 1. Рестартирай мрежовите компоненти
kubectl rollout restart daemonset/svclb-traefik -n kube-system
kubectl rollout restart deployment/coredns -n kube-system

# 2. Почисти iptables правилата
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F

# 3. Рестартирай K3s за пълно възстановяване
sudo systemctl restart k3s
sudo systemctl restart k3s-agent

# 4. Провери мрежовите политики
kubectl get networkpolicy --all-namespaces
kubectl delete networkpolicy --all # Внимание: само за тестване!
```
#### **Тест на Мрежовата Свързаност:**
```
bash
# Създай тестови подове
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-test-1
spec:
  containers:
  - name: busybox
    image: busybox
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: network-test-2
spec:
  containers:
  - name: busybox
    image: busybox
    command: ["sleep", "3600"]
EOF

# Тествай свързаността между подовете
kubectl exec network-test-1 -- ping -c 3 $(kubectl get pod network-test-2 -o jsonpath='{.status.podIP}')

# Почисти
kubectl delete pod network-test-1 network-test-2
```
---

### ❌ **Проблем: MetalLB LoadBalancer Не Работи**

#### **Симптоми:**
```
bash
# Услугите остават в Pending състояние
kubectl get svc | grep LoadBalancer | grep "<pending>"

# Няма външни IP адреси
kubectl get svc portainer -o wide
```
#### **Диагностика:**
```
bash
# Провери MetalLB инсталацията
kubectl get pods -n metallb-system
kubectl get configmap -n metallb-system

# Провери логовете на MetalLB
kubectl logs -n metallb-system -l app=metallb
kubectl logs -n metallb-system -l component=controller
kubectl logs -n metallb-system -l component=speaker

# Провери IP пула
kubectl get ipaddresspool -n metallb-system -o yaml
```
#### **Решения:**
```
bash
# 1. Преинсталирай MetalLB
kubectl delete namespace metallb-system

# Изчакай изтриването да завърши
kubectl wait --for=delete namespace/metallb-system --timeout=60s

# Преинсталирай
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# 2. Конфигурирай IP пула правилно
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.110  # За ВМ: 192.168.122.100-192.168.122.110
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

# 3. Провери мрежовата свързаност
ping 192.168.1.100  # Трябва да отговори ако IP е зает
```
---

### ❌ **Проблем: DNS Резолюция Не Работи**

#### **Симптоми:**
```
bash
# Внътрешният DNS не работи
kubectl exec -it test-pod -- nslookup kubernetes.default.svc.cluster.local
# nslookup: can't resolve 'kubernetes.default.svc.cluster.local'
```
#### **Диагностика:**
```
bash
# Провери CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl describe pod -n kube-system -l k8s-app=kube-dns

# Провери конфигурацията на CoreDNS
kubectl get configmap coredns -n kube-system -o yaml

# Провери DNS услугата
kubectl get svc -n kube-system kube-dns
```
#### **Решения:**
```
bash
# 1. Рестартирай CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# 2. Провери /etc/resolv.conf в подовете
kubectl run debug-dns --image=busybox --rm -it --restart=Never -- cat /etc/resolv.conf

# 3. Актуализирай CoreDNS конфигурацията
kubectl patch configmap coredns -n kube-system --patch='
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 1.1.1.1
        cache 30
        loop
        reload
        loadbalance
    }
'

# 4. Рестартирай след промяната
kubectl rollout restart deployment/coredns -n kube-system
```
---

## 💾 Проблеми със Съхранението {#storage-issues}

### ❌ **Проблем: PVC Остава в Pending Състояние**

#### **Симптоми:**
```
bash
# PVC не се свързва с PV
kubectl get pvc
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
test-pvc   Pending                                    longhorn       5m
```
#### **Диагностика:**
```
bash
# Провери детайлите на PVC
kubectl describe pvc test-pvc

# Провери наличните PV
kubectl get pv

# Провери Longhorn състоянието
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# Провери Longhorn възлите
kubectl get nodes.longhorn.io -n longhorn-system
```
#### **Решения:**
```
bash
# 1. Провери дискового пространство на възлите
kubectl get nodes.longhorn.io -n longhorn-system -o yaml | grep -A5 -B5 "conditions"

# 2. Рестартирай Longhorn компонентите
kubectl rollout restart daemonset/longhorn-manager -n longhorn-system
kubectl rollout restart deployment/longhorn-ui -n longhorn-system

# 3. Ръчно създай PV ако е необходимо
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: longhorn
  hostPath:
    path: /var/lib/longhorn/manual-volume
EOF

# 4. Почисти проблемни PVC/PV
kubectl delete pvc test-pvc
kubectl patch pv problematic-pv -p '{"spec":{"claimRef":null}}'
```
---

### ❌ **Проблем: Longhorn Не Се Инсталира**

#### **Симптоми:**
```
bash
# Longhorn подовете не стартират
kubectl get pods -n longhorn-system | grep -v Running
```
#### **Диагностика:**
```
bash
# Провери системните изисквания
sudo which iscsiadm
sudo systemctl status iscsid

# Провери достъпа до блокови устройства
lsblk
sudo fdisk -l

# Провери Longhorn логовете
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50
```
#### **Решения:**
```
bash
# 1. Инсталирай необходимите зависимости
sudo apt update
sudo apt install -y open-iscsi util-linux

# 2. Стартирай iSCSI услугата
sudo systemctl enable iscsid
sudo systemctl start iscsid

# 3. Създай Longhorn директория
sudo mkdir -p /var/lib/longhorn
sudo chmod 755 /var/lib/longhorn

# 4. Преинсталирай Longhorn
kubectl delete namespace longhorn-system --wait=true
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

# 5. Изчакай готовността
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
```
---

## 🔒 Проблеми със Сигурността {#security-issues}

### ❌ **Проблем: CrowdSec Не Стартира**

#### **Симптоми:**
```
bash
# CrowdSec под в състояние на грешка
kubectl get pods | grep crowdsec
crowdsec-pod   0/1   CrashLoopBackOff   5   10m
```
#### **Диагностика:**
```
bash
# Провери логовете на CrowdSec
kubectl logs crowdsec-pod

# Провери монтираните томове
kubectl describe pod crowdsec-pod | grep -A10 Volumes

# Провери достъпа до лог файловете
sudo ls -la /var/log/
sudo ls -la /var/log/syslog /var/log/auth.log
```
#### **Решения:**
```
bash
# 1. Актуализирай CrowdSec конфигурацията
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: crowdsec-config
data:
  acquis.yaml: |
    filenames:
      - /var/log/syslog
      - /var/log/auth.log
    labels:
      type: syslog
EOF

# 2. Поправи разрешенията на лог файловете
sudo chmod 644 /var/log/syslog /var/log/auth.log
sudo chown root:adm /var/log/syslog /var/log/auth.log

# 3. Рестартирай CrowdSec пода
kubectl delete pod crowdsec-pod
```
---

### ❌ **Проблем: WireGuard VPN Не Работи**

#### **Симптоми:**
```
bash
# Не можеш да се свържеш към VPN
# Порт 51820 не отговаря
```
#### **Диагностика:**
```
bash
# Провери WireGuard пода
kubectl get pods | grep wireguard
kubectl logs wireguard-pod

# Провери мрежовия достъп
kubectl get svc | grep wireguard
sudo netstat -ulpn | grep 51820

# Провери iptables правилата
sudo iptables -L -n | grep 51820
```
#### **Решения:**
```
bash
# 1. Провери LoadBalancer IP
kubectl get svc wireguard-service -o wide

# 2. Актуализирай защитната стена
sudo ufw allow 51820/udp
sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT

# 3. Рестартирай WireGuard услугата
kubectl rollout restart deployment/wireguard

# 4. Генерирай нова клиентска конфигурация
kubectl exec wireguard-pod -- wg genkey | tee privatekey | wg pubkey > publickey
```
---

## 📊 Проблеми с Производителността {#performance-issues}

### ❌ **Проблем: Високо Използване на CPU/RAM**

#### **Симптоми:**
```
bash
# Възлите са претоварени
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=cpu
```
#### **Диагностика:**
```
bash
# Анализирай използването на ресурсите
kubectl describe nodes | grep -A5 "Allocated resources"

# Провери ресурсните ограничения
kubectl get pods --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,CPU-REQ:.spec.containers[*].resources.requests.cpu,MEM-REQ:.spec.containers[*].resources.requests.memory

# Провери системните процеси
top -o %CPU
free -h
iostat -x 1 5
```
#### **Решения:**
```
bash
# 1. Намали ресурсните заявки за некритични приложения
kubectl patch deployment app-name -p '{"spec":{"template":{"spec":{"containers":[{"name":"container-name","resources":{"requests":{"cpu":"50m","memory":"128Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}}]}}}}'

# 2. Добави хоризонтално автоматично сскалиране
kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-name
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

# 3. Оптимизирай системните настройки
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'net.core.somaxconn=32768' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
---

### ❌ **Проблем: Бавна Мрежова Производителност**

#### **Симптоми:**
```
bash
# Бавни отговори между подовете
# Високо мрежово закъснение
```
#### **Диагностика:**
```
bash
# Тествай мрежовата скорост
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-perf-test
spec:
  containers:
  - name: iperf3
    image: networkstatic/iperf3
    command: ["sleep", "3600"]
EOF

kubectl exec -it network-perf-test -- iperf3 -s &
kubectl exec -it network-perf-test -- iperf3 -c localhost -t 30

# Провери MTU настройките
ip link show | grep mtu
```
#### **Решения за Bare Metal:**
```
bash
# 1. Оптимизирай MTU за Jumbo frames
sudo ip link set dev bond0 mtu 9000
sudo ip link set dev ens3f0 mtu 9000
sudo ip link set dev ens3f1 mtu 9000

# 2. Настрой TCP оптимизации
echo 'net.core.rmem_max = 268435456' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 268435456' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control = bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 3. Оптимизирай network bonding
echo 'alias bond0 bonding' | sudo tee -a /etc/modules
echo 'options bonding mode=802.3ad miimon=100 lacp_rate=fast' | sudo tee -a /etc/modprobe.d/bonding.conf
```
#### **Решения за ВМ:**
```
bash
# 1. Увеличи мрежовите буфери
echo 'net.core.netdev_max_backlog = 5000' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_window_scaling = 1' | sudo tee -a /etc/sysctl.conf

# 2. Оптимизирай виртуалната мрежа
# На хипервизора (KVM пример):
# virsh edit vm-name
# Добави: <driver name='vhost' queues='4'/>
```
---

## 🔧 Проблеми с Управлението {#management-issues}

### ❌ **Проблем: Portainer Не Е Достъпен**

#### **Симптоми:**
```
bash
# Не можеш да достъпиш Portainer UI
# Браузърът показва "Connection refused"
```
#### **Диагностика:**
```
bash
# Провери Portainer пода
kubectl get pods | grep portainer
kubectl describe pod portainer-pod

# Провери услугата
kubectl get svc | grep portainer
kubectl describe svc portainer

# Провери LoadBalancer IP
kubectl get svc portainer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```
#### **Решения:**
```
bash
# 1. Рестартирай Portainer
kubectl rollout restart deployment/portainer

# 2. Провери защитната стена
sudo ufw allow 9000/tcp
sudo iptables -A INPUT -p tcp --dport 9000 -j ACCEPT

# 3. Използвай port-forward като временно решение
kubectl port-forward svc/portainer 9000:9000 &

# 4. Актуализирай LoadBalancer конфигурацията
kubectl patch svc portainer -p '{"spec":{"type":"LoadBalancer","loadBalancerIP":"192.168.1.104"}}'
```
---

### ❌ **Проблем: Dashboard Не Показва Данни**

#### **Симптоми:**
```
bash
# Dashboard UI се зарежда но няма данни
# Грешки в браузърската конзола
```
#### **Диагностика:**
```
bash
# Провери dashboard пода
kubectl get pods | grep dashboard
kubectl logs dashboard-pod

# Провери RBAC разрешенията
kubectl get clusterrolebinding | grep dashboard
kubectl describe clusterrolebinding dashboard-admin
```
#### **Решения:**
```
bash
# 1. Актуализирай RBAC разрешенията
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard
  namespace: default
EOF

# 2. Рестартирай dashboard
kubectl rollout restart deployment/dashboard

# 3. Провери API достъпа
kubectl auth can-i --list --as=system:serviceaccount:default:dashboard
```
---

## 🖥️ Специфични за ВМ Проблеми {#vm-specific-issues}

### ❌ **Проблем: ВМ Скриптът Не Разпознава Ролята**

#### **Симптоми:**
```
bash
# Скриптът не може да определи дали е master или worker
VM Role detected: auto-detect (IP: 192.168.122.50)
```
#### **Диагностика:**
```
bash
# Провери IP конфигурацията
ip addr show
ip route get 8.8.8.8

# Провери променливите на средата
echo $VM_MASTER_IP
echo $VM_WORKER1_IP
echo $VM_WORKER2_IP
```
#### **Решения:**
```
bash
# 1. Задай ролята ръчно
export VM_ROLE="master"  # или "worker"
sudo ./deploy-vm-k3s.sh

# 2. Конфигурирай статични IP адреси
sudo cat > /etc/netplan/01-network.yaml << EOF
network:
  version: 2
  ethernets:
    enp1s0:  # замени с твоя интерфейс
      dhcp4: false
      addresses:
        - 192.168.122.10/24  # master IP
      gateway4: 192.168.122.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF

sudo netplan apply

# 3. Актуализирай променливите
export VM_MASTER_IP="192.168.122.10"
export VM_WORKER1_IP="192.168.122.11"
export VM_WORKER2_IP="192.168.122.12"
```
---

### ❌ **Проблем: Недостатъчни ВМ Ресурси**

#### **Симптоми:**
```
bash
# Подовете са evicted поради недостиг на ресурси
kubectl get events | grep Evicted
```
#### **Диагностика:**
```
bash
# Провери ресурсните ограничения на ВМ
free -h
df -h
kubectl describe nodes | grep -A10 "Capacity\|Allocatable"
```
#### **Решения:**
```
bash
# 1. Увеличи ВМ ресурсите (на хипервизора)
# За VirtualBox:
# VBoxManage modifyvm "VM-name" --memory 4096 --cpus 4

# За VMware:
# Редактирай .vmx файла:
# memsize = "4096"
# numvcpus = "4"

# 2. Оптимизирай ресурсните заявки
kubectl patch deployment app-name -p '{"spec":{"template":{"spec":{"containers":[{"name":"container-name","resources":{"requests":{"cpu":"50m","memory":"64Mi"}}}]}}}}'

# 3. Добави swap (само за тестване)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```
---

## 🏭 Специфични за Bare Metal Проблеми {#barebone-specific-issues}

### ❌ **Проблем: Network Bonding Не Работи**

#### **Симптоми:**
```
bash
# Bonding интерфейсът не се създава
# Слабо мрежово представяне между възлите
```
#### **Диагностика:**
```
bash
# Провери bonding състоянието
cat /proc/net/bonding/bond0
ip link show bond0

# Провери наличните интерфейси
ip link show | grep -E "(ens|eth)"
lspci | grep -i network

# Провери bonding модула
lsmod | grep bonding
```
#### **Решения:**
```
bash
# 1. Зареди bonding модула
sudo modprobe bonding
echo 'bonding' | sudo tee -a /etc/modules

# 2. Създай bonding конфигурация
sudo cat > /etc/netplan/60-bond.yaml << EOF
network:
  version: 2
  ethernets:
    ens3f0:
      dhcp4: false
    ens3f1:
      dhcp4: false
  bonds:
    bond0:
      interfaces: [ens3f0, ens3f1]
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
      addresses:
        - 10.0.0.10/24  # за master
      mtu: 9000
EOF

sudo netplan apply

# 3. Провери свързаността
ping -c 3 10.0.0.11  # ping другия възел
```
---

### ❌ **Проблем: Хардуерни Ограничения**

#### **Симптоми:**
```
bash
# Система не използва всички CPU ядра
# RAM не се разпознава правилно
# Дискове не се виждат
```
#### **Диагностика:**
```
bash
# Провери хардуера
lscpu
free -h
lsblk
lspci
lsusb

# Провери BIOS/UEFI настройките
sudo dmidecode -s system-product-name
sudo dmidecode -t memory
```
#### **Решения:**
```
bash
# 1. Актуализирай системните драйвери
sudo apt update
sudo apt install -y linux-generic-hwe-22.04
sudo apt install -y firmware-linux-nonfree  # ако е необходимо

# 2. Оптимизирай CPU настройките
echo 'performance' | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# 3. Активирай всички CPU ядра
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo 1 | sudo tee $cpu/online
done

# 4. Оптимизирай памет настройките
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo 1 | sudo tee /proc/sys/vm/drop_caches
```
---

## 🛠️ Инструменти за Диагностика

### 📱 **Скрипт за Автоматична Диагностика**
```
bash
#!/bin/bash
# system-health-check.sh - Пълна проверка на системата

echo "🔍 odoo-18 K3s Platform - Проверка на Здравословното Състояние"
echo "============================================================="

check_k3s_status() {
    echo "📊 Проверка на K3s състоянието..."
    
    if systemctl is-active --quiet k3s; then
        echo "✅ K3s master услугата работи"
    else
        echo "❌ K3s master услугата не работи"
        sudo systemctl status k3s --no-pager
    fi
    
    if systemctl is-active --quiet k3s-agent; then
        echo "✅ K3s agent услугата работи"
    else
        echo "⚠️ K3s agent услугата не работи (нормално за master-only възли)"
    fi
}

check_cluster_health() {
    echo "🏥 Проверка на здравословното състояние на клъстера..."
    
    # Провери възлите
    NOT_READY=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
    TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
    
    echo "📊 Готови възли: $((TOTAL_NODES - NOT_READY))/$TOTAL_NODES"
    
    # Провери подовете
    FAILING_PODS=$(kubectl get pods --all-namespaces --no-headers | grep -E "(Error|CrashLoop|Pending)" | wc -l)
    TOTAL_PODS=$(kubectl get pods --all-namespaces --no-headers | wc -l)
    
    echo "📊 Работещи подове: $((TOTAL_PODS - FAILING_PODS))/$TOTAL_PODS"
    
    if [ $FAILING_PODS -gt 0 ]; then
        echo "❌ Проблемни подове:"
        kubectl get pods --all-namespaces | grep -E "(Error|CrashLoop|Pending)"
    fi
}

check_storage_health() {
    echo "💾 Проверка на съхранението..."
    
    # Провери Longhorn
    if kubectl get namespace longhorn-system >/dev/null 2>&1; then
        LONGHORN_PODS=$(kubectl get pods -n longhorn-system --no-headers | grep -v Running | wc -l)
        if [ $LONGHORN_PODS -eq 0 ]; then
            echo "✅ Longhorn работи правилно"
        else
            echo "❌ Longhorn има проблеми"
            kubectl get pods -n longhorn-system | grep -v Running
        fi
    else
        echo "⚠️ Longhorn не е инсталиран"
    fi
    
    # Провери PVC
    PENDING_PVCS=$(kubectl get pvc --all-namespaces --no-headers | grep Pending | wc -l)
    if [ $PENDING_PVCS -eq 0 ]; then
        echo "✅ Всички PVC са свързани"
    else
        echo "❌ $PENDING_PVCS PVC са в състояние на чакане"
    fi
}

check_network_health() {
    echo "🌐 Проверка на мрежата..."
    
    # Провери CoreDNS
    COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep Running | wc -l)
    if [ $COREDNS_READY -gt 0 ]; then
        echo "✅ CoreDNS работи"
    else
        echo "❌ CoreDNS не работи"
    fi
    
    # Провери MetalLB
    if kubectl get namespace metallb-system >/dev/null 2>&1; then
        METALLB_READY=$(kubectl get pods -n metallb-system --no-headers | grep Running | wc -l)
        METALLB_TOTAL=$(kubectl get pods -n metallb-system --no-headers | wc -l)
        
        if [ $METALLB_READY -eq $METALLB_TOTAL ]; then
            echo "✅ MetalLB работи ($METALLB_READY/$METALLB_TOTAL подове)"
        else
            echo "❌ MetalLB има проблеми ($METALLB_READY/$METALLB_TOTAL подове готови)"
        fi
    else
        echo "⚠️ MetalLB не е инсталиран"
    fi
}

check_security_health() {
    echo "🔒 Проверка на сигурността..."
    
    # Провери CrowdSec
    if kubectl get pods | grep -q crowdsec; then
        if kubectl get pods | grep crowdsec | grep -q Running; then
            echo "✅ CrowdSec работи"
        else
            echo "❌ CrowdSec не работи"
        fi
    else
        echo "⚠️ CrowdSec не е разгърнат"
    fi
    
    # Провери WireGuard
    if kubectl get pods | grep -q wireguard; then
        if kubectl get pods | grep wireguard | grep -q Running; then
            echo "✅ WireGuard работи"
        else
            echo "❌ WireGuard не работи"
        fi
    else
        echo "⚠️ WireGuard не е разгърнат"
    fi
}

check_resource_usage() {
    echo "📊 Проверка на използването на ресурсите..."
    
    # Провери системните ресурси
    MEMORY_USAGE=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
    DISK_USAGE=$(df / | awk 'NR==2 {printf "%.1f", $5}' | sed 's/%//')
    
    echo "💾 Използване на паметта: ${MEMORY_USAGE}%"
    echo "💿 Използване на диска: ${DISK_USAGE}%"
    
    # Предупреждения
    if (( $(echo "$MEMORY_USAGE > 85" | bc -l) )); then
        echo "⚠️ Високо използване на паметта!"
    fi
    
    if (( $(echo "$DISK_USAGE > 80" | bc -l) )); then
        echo "⚠️ Високо използване на диска!"
    fi
}

generate_report() {
    echo ""
    echo "📋 Резюме:"
    echo "=========="
    
    # Генерирай общ статус
    ISSUES=0
    
    # Провери за проблеми и увеличи брояча
    if ! systemctl is-active --quiet k3s; then
        ((ISSUES++))
    fi
    
    NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v Ready | wc -l)
    ISSUES=$((ISSUES + NOT_READY))
    
    FAILING_PODS=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -E "(Error|CrashLoop|Pending)" | wc -l)
    ISSUES=$((ISSUES + FAILING_PODS))
    
    if [ $ISSUES -eq 0 ]; then
        echo "🎉 Системата работи отлично! Няма открити проблеми."
    elif [ $ISSUES -le 3 ]; then
        echo "⚠️ Открити са малки проблеми ($ISSUES). Препоръчва се проверка."
    else
        echo "❌ Открити са сериозни проблеми ($ISSUES). Необходима е спешна намеса."
    fi
    
    echo ""
    echo "📞 За помощ: support@odoo-18.com"
    echo "📚 Документация: https://github.com/odoo-18/k3s-platform/docs/"
}

# Изпълни всички проверки
check_k3s_status
echo ""
check_cluster_health
echo ""
check_storage_health
echo ""
check_network_health
echo ""
check_security_health
echo ""
check_resource_usage
echo ""
generate_report
```
### 🔧 **Скрипт за Бързо Възстановяване**
```
bash
#!/bin/bash
# quick-recovery.sh - Бързо възстановяване на услуги

echo "🚨 odoo-18 K3s Platform - Бързо Възстановяване"
echo "==============================================="

restart_core_services() {
    echo "🔄 Рестартиране на основните услуги..."
    
    # Рестартирай K3s
    sudo systemctl restart k3s
    sleep 10
    
    # Рестартирай важните компоненти
    kubectl rollout restart deployment/coredns -n kube-system
    kubectl rollout restart daemonset/svclb-traefik -n kube-system
    
    echo "✅ Основните услуги са рестартирани"
}

fix_networking() {
    echo "🌐 Поправка на мрежовите проблеми..."
    
    # Почисти iptables
    sudo iptables -F
    sudo iptables -t nat -F
    
    # Рестартирай мрежовите услуги
    sudo systemctl restart networking
    sudo systemctl restart systemd-resolved
    
    echo "✅ Мрежовите проблеми са решени"
}

clear_failed_pods() {
    echo "🧹 Почистване на неуспешни подове..."
    
    # Изтрий неуспешни подове
    kubectl delete pods --field-selector=status.phase=Failed --all-namespaces
    kubectl delete pods --field-selector=status.phase=Succeeded --all-namespaces
    
    # Рестартирай проблемни подове
    kubectl get pods --all-namespaces | grep -E "(Error|CrashLoop)" | awk '{print $2 " -n " $1}' | xargs -r kubectl delete pod
    
    echo "✅ Неуспешните подове са почистени"
}

# Меню за избор
echo "Изберете опция за възстановяване:"
echo "1) Рестартиране на основните услуги"
echo "2) Поправка на мрежовите проблеми" 
echo "3) Почистване на неуспешни подове"
echo "4) Пълно възстановяване (всички опции)"
echo "0) Излез"

read -p "Въведете номер: " choice

case $choice in
    1) restart_core_services ;;
    2) fix_networking ;;
    3) clear_failed_pods ;;
    4) 
        restart_core_services
        echo ""
        fix_networking
        echo ""
        clear_failed_pods
        ;;
    0) echo "Излизане..."; exit 0 ;;
    *) echo "Невалиден избор"; exit 1 ;;
esac

echo ""
echo "🎉 Възстановяването завърши!"
echo "Изчакайте 1-2 минути за стабилизиране на услугите."
```
---

## 📞 Получаване на Помощ

### 🆘 **Стъпки за Получаване на Поддръжка**

1. **🔍 Първо опитайте автоматичната диагностика:**
   ```bash
   wget -O system-health-check.sh https://raw.githubusercontent.com/odoo-18/k3s-platform/main/scripts/system-health-check.sh
   chmod +x system-health-check.sh
   sudo ./system-health-check.sh
   ```

2. **📋 Съберете диагностична информация:**
   ```bash
   # Създайте диагностичен пакет
   mkdir -p ~/odoo-18-support
   
   # Системна информация
   uname -a > ~/odoo-18-support/system-info.txt
   lsb_release -a >> ~/odoo-18-support/system-info.txt
   
   # K3s информация
   kubectl get nodes -o wide > ~/odoo-18-support/nodes.txt
   kubectl get pods --all-namespaces > ~/odoo-18-support/pods.txt
   kubectl get events --all-namespaces > ~/odoo-18-support/events.txt
   
   # Логове
   sudo journalctl -u k3s --since "1 hour ago" > ~/odoo-18-support/k3s-logs.txt
   
   # Архивирайте всичко
   tar -czf odoo-18-support-$(date +%Y%m%d-%H%M%S).tar.gz -C ~ odoo-18-support/
   ```

3. **📧 Свържете се с поддръжката:**
   - **Имейл**: vladimirov.rosen@gmail.com
   - **Форум**: https://github.com/rosenvladimirov/discussions
   - **Спешност**: +359-886-100-204
   - **Билети**: https://support.odoo-shell.dev

### 📚 **Допълнителни Ресурси**

- **[🚀 Основен README](README.md)** - Преглед на платформата
- **[🏭 Bare Metal Ръководство](README-BAREBONE.md)** - Специфични инструкции
- **[🖥️ ВМ Ръководство](README-VM.md)** - ВМ конфигурация
- **[🔄 Ръководство за Миграция](MIGRATION-GUIDE.md)** - Миграция между сценарии
- **[📖 Wiki](https://github.com/username/k3s-odoo-platformform/wiki)** - Разширена документация

---

**Бързо Решение. Експертна Поддръжка. Непрекъсната Работа.** 🚀🔧

**odoo-18 Техническа Поддръжка** - *24/7 Експертиза За Вашия Успех* ⚡🎯