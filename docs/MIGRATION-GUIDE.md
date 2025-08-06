---
layout: default
title: "Миграционно Ръководство"
nav_order: 4
---

# 🔄 Ръководство за Миграция - Odoo-18 K3s Платформа

**Пълно ръководство за миграция между Bare Metal и VM разгръщане сценарии**

## 🎯 Преглед

Това ръководство описва как да **мигрирате безопасно** между различните разгръщане сценарии на Odoo-18 K3s Платформа. Поддържаме **двупосочна миграция** с минимално спиране на услугите и запазване на данните.

---

## 📋 Поддържани Миграционни Пътища

### 🔄 **Типове Миграция**

| От | Към | Сложност | Време | Спиране |
|----|-----|----------|-------|---------|
| **🖥️ ВМ → 🏭 Bare Metal** | Производствено мащабиране | **Средна** | 2-4 часа | 30-60 мин |
| **🏭 Bare Metal → 🖥️ ВМ** | Разработка/тестване | **Ниска** | 1-2 часа | 15-30 мин |
| **🖥️ ВМ → 🖥️ ВМ** | Хардуерна промяна | **Ниска** | 1-2 часа | 15-30 мин |
| **🏭 Bare Metal → 🏭 Bare Metal** | Хардуерно подобрение | **Висока** | 4-8 часа | 60-120 мин |

---

## 🚀 Миграция: ВМ към Bare Metal

> **Сценарий:** Повишаване от разработка/тестване към производствена среда

### 📋 **Предварителни Изисквания**

#### **🔧 Bare Metal Хардуер**
- **Сървъри**: 2+ физически сървъра
- **Мрежа**: Множество мрежови интерфейси за свързване
- **Съхранение**: Допълнителни дискове за Longhorn
- **RAM**: 8GB+ на сървър
- **Процесор**: 4+ ядра на сървър

#### **📝 Подготовка**
```
bash
# 1. Документирай текущата ВМ конфигурация
kubectl get nodes -o wide > vm-cluster-nodes.txt
kubectl get pods --all-namespaces > vm-cluster-pods.txt
kubectl get pvc --all-namespaces > vm-cluster-storage.txt

# 2. Архивирай конфигурации
mkdir -p migration-backup/vm-config
kubectl get configmaps --all-namespaces -o yaml > migration-backup/vm-config/configmaps.yaml
kubectl get secrets --all-namespaces -o yaml > migration-backup/vm-config/secrets.yaml

# 3. Архивиране на приложни данни
kubectl get pv -o yaml > migration-backup/vm-config/persistent-volumes.yaml
```
### 🔧 **Стъпка 1: Архивиране на Данни**

#### **Архивиране на Клъстер Данни**
```
bash
# Спри приложенията временно за консистентност
kubectl scale deployment --all --replicas=0 --all-namespaces

# Архивиране на Longhorn томове
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: BackupTarget
metadata:
  name: migration-backup
  namespace: longhorn-system
spec:
  backupTargetURL: file:///backup/longhorn
  credentialSecret: ""
EOF

# Създай архив на всички томове
kubectl get pv | grep longhorn | awk '{print $1}' | while read pv; do
  kubectl patch pv $pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
```
#### **Архивиране на Kubernetes Обекти**
```
bash
# Архивиране на всички Kubernetes ресурси
mkdir -p migration-backup/k8s-resources

# Архивиране на namespace-level ресурси
for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
  mkdir -p "migration-backup/k8s-resources/$ns"
  
  # Разгръщания
  kubectl get deployments -n $ns -o yaml > "migration-backup/k8s-resources/$ns/deployments.yaml"
  
  # Услуги
  kubectl get services -n $ns -o yaml > "migration-backup/k8s-resources/$ns/services.yaml"
  
  # Конфигурационни карти
  kubectl get configmaps -n $ns -o yaml > "migration-backup/k8s-resources/$ns/configmaps.yaml"
  
  # Тайни (внимавай със чувствителни данни)
  kubectl get secrets -n $ns -o yaml > "migration-backup/k8s-resources/$ns/secrets.yaml"
  
  # Постоянни заявки за том
  kubectl get pvc -n $ns -o yaml > "migration-backup/k8s-resources/$ns/pvcs.yaml"
done

# Архивиране на cluster-level ресурси
kubectl get clusterroles -o yaml > migration-backup/k8s-resources/clusterroles.yaml
kubectl get clusterrolebindings -o yaml > migration-backup/k8s-resources/clusterrolebindings.yaml
kubectl get persistentvolumes -o yaml > migration-backup/k8s-resources/persistentvolumes.yaml
```
### 🏭 **Стъпка 2: Разгръщане на Bare Metal Клъстер**

#### **Подготовка на Bare Metal Сървъри**
```
bash
# На всеки Bare Metal сървър
# 1. Инсталирай Ubuntu Server 22.04 LTS
# 2. Конфигурирай мрежовите интерфейси
# 3. Подготви допълнителните дискове

# Изтегли разгръщане скрипта
wget https://raw.githubusercontent.com/rosenvladimirov/odoo-18/main/barebone/deploy-hybrid-k3s.sh
chmod +x deploy-hybrid-k3s.sh

# Конфигурирай променливи на средата за миграция
export MIGRATION_MODE="true"
export SOURCE_CLUSTER_TYPE="vm"
export RESTORE_FROM_BACKUP="true"
export BACKUP_LOCATION="/path/to/migration-backup"
```
#### **Разгръщане на Bare Metal Главен Възел**
```
bash
# На Bare Metal Главен сървър
sudo ./deploy-hybrid-k3s.sh master

# Скриптът ще:
# ✅ Конфигурира мрежово свързване
# ✅ Настрои високопроизводителна мрежа
# ✅ Инсталира K3s с производствени настройки
# ✅ Разгърне MetalLB с производствен IP пул
# ✅ Подготви за възстановяване на данни
```
#### **Разгръщане на Bare Metal Работници**
```
bash
# На всеки Bare Metal Работник сървър
sudo ./deploy-hybrid-k3s.sh worker

# Провери състоянието на клъстера
kubectl get nodes
kubectl get pods --all-namespaces
```
### 📦 **Стъпка 3: Възстановяване на Данни**

#### **Възстановяване на Kubernetes Ресурси**
```
bash
# Копирай архивни данни на новия клъстер
scp -r migration-backup/ root@bare-metal-master:/tmp/

# На Bare Metal Главен възел
cd /tmp/migration-backup

# Възстанови пространства от имена първо
kubectl apply -f k8s-resources/*/namespace.yaml

# Възстанови конфигурационни карти и тайни
for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
  if [ -f "k8s-resources/$ns/configmaps.yaml" ]; then
    kubectl apply -f "k8s-resources/$ns/configmaps.yaml"
  fi
  
  if [ -f "k8s-resources/$ns/secrets.yaml" ]; then
    kubectl apply -f "k8s-resources/$ns/secrets.yaml"
  fi
done

# Възстанови заявки за постоянни томове (ще се създадат нови постоянни томове)
for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
  if [ -f "k8s-resources/$ns/pvcs.yaml" ]; then
    kubectl apply -f "k8s-resources/$ns/pvcs.yaml"
  fi
done
```
#### **Възстановяване на Приложни Данни**
```
bash
# Възстанови данни от Longhorn том
# Метод 1: Директно копиране на файлове на том
rsync -avP /vm-backup/longhorn-data/ /var/lib/longhorn/

# Метод 2: Възстановяване от Longhorn архив (препоръчително)
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Restore
metadata:
  name: migration-restore
  namespace: longhorn-system
spec:
  fromBackup: "migration-backup"
EOF
```
#### **Възстановяване на Приложения**
```
bash
# Възстанови разгръщания и услуги
for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
  if [ -f "k8s-resources/$ns/deployments.yaml" ]; then
    kubectl apply -f "k8s-resources/$ns/deployments.yaml"
  fi
  
  if [ -f "k8s-resources/$ns/services.yaml" ]; then
    kubectl apply -f "k8s-resources/$ns/services.yaml"
  fi
done

# Провери състоянието на приложенията
kubectl get pods --all-namespaces
kubectl get pvc --all-namespaces
```
### ✅ **Стъпка 4: Валидация и Тестване**

#### **Функционален Тест**
```
bash
# Провери здравословното състояние на клъстера
kubectl get nodes
kubectl top nodes
kubectl get pods --all-namespaces | grep -v Running

# Тествай мрежата
kubectl run test-pod --image=nginx --rm -it --restart=Never -- curl http://kubernetes.default.svc.cluster.local

# Тествай съхранението
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc test-pvc
kubectl delete pvc test-pvc
```
#### **Тест на Производителността**
```
bash
# Тествай мрежовата производителност
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-test
spec:
  containers:
  - name: iperf
    image: networkstatic/iperf3
    command: ["sleep", "3600"]
EOF

# Влез в пода и тествай
kubectl exec -it network-test -- iperf3 -s &
kubectl exec -it network-test -- iperf3 -c localhost -t 30
```
---

## 🖥️ Миграция: Bare Metal към ВМ

> **Сценарий:** Понижаване към разработка/тестване или временно решение

### 📋 **Предварителни Изисквания**

#### **🖥️ ВМ Среда**
- **Хипервизор**: VMware, VirtualBox, KVM
- **ВМ Ресурси**: 4GB+ RAM, 2+ процесор на ВМ
- **Мрежа**: Мостова или host-only мрежа
- **Съхранение**: 20GB+ на ВМ

### 🔧 **Стъпка 1: Подготовка за Намаляване**

#### **Анализ на Ресурсите**
```
bash
# Провери текущото използване на ресурси
kubectl top nodes
kubectl top pods --all-namespaces

# Идентифицирай ресурсно-интензивни приложения
kubectl get pods --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,CPU-REQ:.spec.containers[*].resources.requests.cpu,MEM-REQ:.spec.containers[*].resources.requests.memory

# Намали заявките за ресурси където е възможно
kubectl patch deployment high-resource-app -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"100m","memory":"256Mi"}}}]}}}}'
```
#### **Планиране на ВМ Ресурси**
```
bash
# Изчисли необходимите ВМ ресурси
echo "Текущо използване на ресурси на клъстера:"
kubectl describe nodes | grep -A5 "Allocated resources"

# Създай план за ВМ разпределение
cat > vm-resource-plan.txt << EOF
Главна ВМ: 4GB RAM, 2 процесорни ядра, 20GB диск
Работник1 ВМ: 2GB RAM, 2 процесорни ядра, 15GB диск  
Работник2 ВМ: 2GB RAM, 2 процесорни ядра, 15GB диск
Общо: 8GB RAM, 6 процесорни ядра, 50GB диск
EOF
```
### 🖥️ **Стъпка 2: Създаване на ВМ Среда**

#### **Създаване на ВМ**
```
bash
# Създай ВМ-та според плана
# Главна ВМ: 192.168.122.10
# Работник1 ВМ: 192.168.122.11
# Работник2 ВМ: 192.168.122.12

# На всяка ВМ инсталирай Ubuntu Server 22.04
# Конфигурирай статични IP адреси
# Активирай SSH достъп
```
#### **Разгръщане на ВМ Клъстер**
```
bash
# Изтегли ВМ разгръщане скрипта
wget https://raw.githubusercontent.com/rosenvladimirov/odoo-18/main/vm/deploy-vm-k3s.sh
chmod +x deploy-vm-k3s.sh

# Разгърни Главна ВМ
sudo ./deploy-vm-k3s.sh master

# Разгърни Работник ВМ-та
sudo ./deploy-vm-k3s.sh worker
```
### 📦 **Стъпка 3: Миграция на Данни**

#### **Архивиране от Bare Metal**
```
bash
# Използвай същия процес на архивиране както в ВМ→Bare Metal миграция
# Архивиране на данни, конфигурации и Kubernetes обекти
mkdir -p migration-backup/bare-metal-config
kubectl get all --all-namespaces -o yaml > migration-backup/bare-metal-config/all-resources.yaml
```
#### **Възстановяване на ВМ Клъстер**
```
bash
# Копирай архивни данни на ВМ клъстер
scp -r migration-backup/ root@192.168.122.10:/tmp/

# Възстанови Kubernetes ресурси
kubectl apply -f migration-backup/bare-metal-config/
```
---

## 🔧 Миграционни Помощни Програми

### 📱 **Помощни Скриптове за Миграция**

#### **Скрипт за Проверка на Миграция**
```
bash
#!/bin/bash
# migration-checker.sh - Проверява готовността за миграция

check_cluster_health() {
    echo "🔍 Проверяване на здравословното състояние на клъстера..."
    
    # Провери възли
    NOT_READY=$(kubectl get nodes | grep -v Ready | wc -l)
    if [ $NOT_READY -gt 1 ]; then
        echo "❌ $((NOT_READY-1)) възли не са готови"
        return 1
    fi
    
    # Провери подове
    FAILING_PODS=$(kubectl get pods --all-namespaces | grep -E "(Error|CrashLoop|Pending)" | wc -l)
    if [ $FAILING_PODS -gt 0 ]; then
        echo "❌ $FAILING_PODS подове имат проблеми"
        return 1
    fi
    
    echo "✅ Здравословното състояние на клъстера е добро"
    return 0
}

check_storage_health() {
    echo "🔍 Проверяване на здравословното състояние на съхранението..."
    
    # Провери заявки за постоянни томове
    PENDING_PVCS=$(kubectl get pvc --all-namespaces | grep Pending | wc -l)
    if [ $PENDING_PVCS -gt 0 ]; then
        echo "❌ $PENDING_PVCS заявки за постоянни томове са в състояние на чакане"
        return 1
    fi
    
    echo "✅ Здравословното състояние на съхранението е добро"
    return 0
}

estimate_migration_time() {
    echo "⏱️ Оценка на времето за миграция..."
    
    # Изчисли размер на данните
    TOTAL_PV_SIZE=$(kubectl get pv -o jsonpath='{.items[*].spec.capacity.storage}' | tr ' ' '\n' | sed 's/Gi//g' | awk '{sum+=$1} END {print sum}')
    
    echo "📊 Общ размер на данните: ${TOTAL_PV_SIZE}GB"
    echo "⏱️ Очаквано време: $((TOTAL_PV_SIZE / 10)) минути за прехвърляне на данни"
}

# Основно изпълнение
echo "🔄 Проверка за Готовност за Миграция"
echo "=========================="

check_cluster_health || exit 1
check_storage_health || exit 1
estimate_migration_time

echo ""
echo "✅ Клъстерът е готов за миграция!"
```
#### **Скрипт за Възвръщане**
```
bash
#!/bin/bash
# migration-rollback.sh - Възвръщане при неуспешна миграция

rollback_to_source() {
    local SOURCE_TYPE=$1
    local BACKUP_DIR=$2
    
    echo "🔄 Започваме възвръщане към $SOURCE_TYPE клъстер..."
    
    # Спри новия клъстер
    if [ "$SOURCE_TYPE" = "vm" ]; then
        echo "Спираме bare metal клъстер..."
        systemctl stop k3s
        systemctl stop k3s-agent
    else
        echo "Спираме ВМ клъстер..."
        systemctl stop k3s
        systemctl stop k3s-agent
    fi
    
    # Стартирай стария клъстер
    echo "Стартираме оригиналния $SOURCE_TYPE клъстер..."
    # Имплементацията зависи от специфичната настройка
    
    echo "✅ Възвръщането завърши"
}

# Използване
if [ $# -ne 2 ]; then
    echo "Използване: $0 <source_type> <backup_directory>"
    echo "Пример: $0 vm /backup/migration-backup"
    exit 1
fi

rollback_to_source $1 $2
```
### 📊 **Мониторинг на Миграция**

#### **Проследяване на Прогреса**
```
bash
#!/bin/bash
# migration-monitor.sh - Мониторинг на прогреса на миграцията

monitor_data_transfer() {
    local SOURCE_DIR=$1
    local DEST_DIR=$2
    
    while true; do
        SOURCE_SIZE=$(du -sb $SOURCE_DIR 2>/dev/null | cut -f1)
        DEST_SIZE=$(du -sb $DEST_DIR 2>/dev/null | cut -f1)
        
        if [ -n "$SOURCE_SIZE" ] && [ -n "$DEST_SIZE" ]; then
            PROGRESS=$((DEST_SIZE * 100 / SOURCE_SIZE))
            echo "📊 Прогрес на прехвърляне на данни: ${PROGRESS}%"
        fi
        
        sleep 30
    done
}

monitor_cluster_readiness() {
    echo "🔍 Мониторинг на готовността на клъстера..."
    
    while true; do
        READY_NODES=$(kubectl get nodes | grep Ready | wc -l)
        TOTAL_NODES=$(kubectl get nodes | tail -n +2 | wc -l)
        
        echo "📊 Готови възли: $READY_NODES/$TOTAL_NODES"
        
        if [ $READY_NODES -eq $TOTAL_NODES ]; then
            echo "✅ Всички възли са готови!"
            break
        fi
        
        sleep 15
    done
}

# Започни мониторинг
monitor_cluster_readiness &
MONITOR_PID=$!

# Изчакай потребителя да завърши миграцията
read -p "Натисни Enter когато миграцията завърши..."

# Спри мониторинга
kill $MONITOR_PID 2>/dev/null
echo "🏁 Мониторингът на миграцията завърши"
```
---

## 🚨 Отстраняване на Неизправности

### ❌ **Общи Проблеми**

#### **Проблем: Проблеми с Мрежовата Свързаност**
```
bash
# Симптоми: Подовете не могат да комуникират
# Решение:
kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide

# Провери мрежовите политики
kubectl get networkpolicies --all-namespaces

# Рестартирай мрежовите компоненти
kubectl rollout restart daemonset/traefik -n kube-system
kubectl rollout restart deployment/coredns -n kube-system
```
#### **Проблем: Неуспешно Монтиране на Съхранението**
```
bash
# Симптоми: Заявките за постоянни томове остават в състояние на чакане
# Решение:
kubectl describe pvc problematic-pvc

# Провери състоянието на Longhorn
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# Ръчно прикачи томове
kubectl patch pv pv-name -p '{"spec":{"claimRef":null}}'
```
#### **Проблем: Ограничения на Ресурсите**
```
bash
# Симптоми: Подове в състояние на чакане поради недостатъчни ресурси
# Решение:
kubectl describe nodes
kubectl top nodes
kubectl top pods --all-namespaces

# Намали заявките за ресурси
kubectl patch deployment app-name -p '{"spec":{"template":{"spec":{"containers":[{"name":"container-name","resources":{"requests":{"cpu":"50m","memory":"128Mi"}}}]}}}}'
```
### 🔧 **Специфични за Миграция Проблеми**

#### **Проблем: Непълно Прехвърляне на Данни**
```bash
# Проверка за липсващи данни
find /var/lib/longhorn -name "*.img" -size 0
kubectl get pv | grep Available

# Повтори прехвърлянето на данни
rsync -avP --partial source-dir/ dest-dir/
```
```


#### **Проблем: Проблеми с Откриване на Услуги**
```shell script
# Провери DNS резолюцията
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local

# Рестартирай CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
```


---

## 📋 Списък за Проверка на Миграция

### ✅ **Списък за Проверка Преди Миграция**

- [ ] **📊 Планиране на Ресурси**
  - [ ] Изчислени изисквания за ресурси
  - [ ] Планирана мрежова схема
  - [ ] Избрани хардуерни/ВМ спецификации

- [ ] **📦 Подготовка за Архивиране**
  - [ ] Архивиране на всички Kubernetes ресурси
  - [ ] Архивиране на постоянни данни
  - [ ] Архивиране на конфигурации и тайни
  - [ ] Тестван процес на възстановяване

- [ ] **🔧 Подготовка на Средата**
  - [ ] Подготвена целева среда (Bare Metal или ВМ)
  - [ ] Конфигурирана мрежа
  - [ ] Инсталирани необходими зависимости
  - [ ] Тествана свързаност

- [ ] **👥 Координация на Екипа**
  - [ ] Уведомени заинтересовани страни
  - [ ] Планиран прозорец за поддръжка
  - [ ] Подготвен план за възвръщане
  - [ ] Назначени роли на миграционния екип

### ✅ **Списък за Проверка По Време на Миграция**

- [ ] **🔄 Фаза на Изпълнение**
  - [ ] Спрени некритични приложения
  - [ ] Извършено финално архивиране
  - [ ] Започнато разгръщане на целевия клъстер
  - [ ] Мониторинг на прогреса

- [ ] **📦 Фаза на Прехвърляне на Данни**
  - [ ] Потвърдена цялостност на данните
  - [ ] Тествана свързаност на съхранението
  - [ ] Възстановени Kubernetes ресурси
  - [ ] Валидирана функционалност на приложенията

### ✅ **Списък за Проверка След Миграция**

- [ ] **✅ Фаза на Валидация**
  - [ ] Всички възли са готови
  - [ ] Всички подове работят
  - [ ] Съхранението е функционално
  - [ ] Мрежовата свързаност работи
  - [ ] Услугите са достъпни

- [ ] **📊 Тестване на Производителността**
  - [ ] Тестване на натоварването на приложенията
  - [ ] Валидация на мрежовата производителност
  - [ ] Тестване на входа/изхода на съхранението
  - [ ] Проверки на използването на ресурсите

- [ ] **📝 Актуализация на Документацията**
  - [ ] Актуализирани мрежови диаграми
  - [ ] Актуализирани процедури за разгръщане
  - [ ] Актуализирана информация за контакт
  - [ ] Научени уроци от миграцията

---

## 📞 Поддръжка

### 🆘 **Помощ за Миграция**

За помощ с миграцията:
- 📧 **Имейл**: vladimirov.rosen@gmail.com
- 📱 **Спешност**: +359-886-100-204
- 💬 **Чат**: https://chat.odoo-shell.dev/migration-help
- 📋 **Билети**: https://support.odoo-shell.dev

### 📚 **Допълнителни Ресурси**

- **[🏭 Ръководство за Bare Metal](README-BAREBONE.md)** - Подробно ръководство за bare metal
- **[🖥️ ВМ Ръководство](README-VM.md)** - Подробно ВМ ръководство  
- **[🔧 Отстраняване на Неизправности](TROUBLESHOOTING.md)** - Общи проблеми и решения
- **[📖 Най-добри Практики](best-practices/)** - Препоръчителни практики

---

**Безопасна Миграция. Непрекъсната Услуга. Оптимизирана Производителност.** 🚀🔄

**Odoo-18 Услуги за Миграция** - *Експертна Поддръжка За Всяка Стъпка* ⚡🎯