# devops-lab1

## Архитектура

| ВМ | IP | Роль | Проброс на хост |
|---|---|---|---|
| etcd01 | 192.168.56.10 | etcd (DCS для Patroni), HAProxy | 5432 → 5432 |
| pgsql01 | 192.168.56.11 | PostgreSQL 17 + Patroni | 6432 → 5432 |
| pgsql02 | 192.168.56.12 | PostgreSQL 17 + Patroni | 7432 → 5432 |
| k3s01 | 192.168.56.20 | k3s, ingress-nginx, Ansible, мониторинг | 80, 443 |

Все ВМ — Oracle Linux 9, на каждой работает node_exporter (порт 9100).

## Реализация по пунктам задания

| Пункт | Реализация | Файлы |
|---|---|---|
| 1.1–1.2 ВМ и порты | 4 ВМ Oracle Linux 9 (libvirt/KVM), сеть 192.168.56.0/24, проброс портов на localhost хоста | `Vagrantfile` |
| 1.3 Ansible | пользователь `ansible` с ключом и sudo создаётся провиженингом Vagrant, Ansible на k3s01 | `Vagrantfile`, `ansible/ansible.cfg`, `ansible/inventory.yml` |
| 2.1 etcd | etcd 3.6 из бинарника, systemd, один узел | `ansible/etcd.yml`, `ansible/templates/` |
| 2.2 PostgreSQL + Patroni | PostgreSQL 17 (PGDG), Patroni 4 в venv; pgsql01 инициализирует кластер, pgsql02 — streaming-реплика | `ansible/patroni.yml`, `ansible/templates/` |
| 2.3 HAProxy | проверка `/primary` API Patroni, `on-marked-down shutdown-sessions` | `ansible/haproxy.yml`, `ansible/templates/` |
| 2.4 Пользователь и БД | идемпотентный SQL, выполняется только на Primary | `ansible/db.yml`, `ansible/sqls/test-user.sql` |
| 2.5 pg_stat_statements | `shared_preload_libraries` и `track = all` в конфиге Patroni, расширение в `postgres` и `test_db1` | `ansible/sqls/pgstat.sql` |
| 2.6 svc_monitoring | роль `pg_monitor`, без SUPERUSER, лимит подключений | `ansible/sqls/svcmon.sql` |
| 2.7 Failover | см. раздел «Проверка отказоустойчивости» | `docs/failover/` |
| 3.1 k3s | k3s (stable) без Traefik, ingress-nginx, самоподписанный `*.lab.local` в TLS Secret, namespace `monitoring` | `ansible/k3s.yml`, `k8s/namespace.yaml` |
| 3.2 Prometheus, Grafana | Deployment + PVC (`local-path`) + Ingress с TLS, `strategy: Recreate` | `k8s/prometheus.yaml`, `k8s/grafana.yaml`, `ansible/monitoring.yml` |
| 3.3 Сбор метрик | node_exporter на всех ВМ (systemd); postgres_exporter в k3s через HAProxy под svc_monitoring; учётные данные только в Secrets; дашборды 1860 и 9628 через provisioning | `ansible/node_exporter.yml`, `k8s/postgres-exporter.yaml`, `k8s/dashboards/` |

При выполнении использовался ИИ-ассистент для подготовки конфигураций
и диагностики

## 0. Хост

Хост Vagrant — Linux с поддержкой KVM: 
ВМ Google Cloud n2-standard-4 (4 vCPU / 16 ГБ, Debian 12) с вложенной виртуализацией.


## 1. Подготовка хоста

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients \
  vagrant vagrant-libvirt git rsync postgresql-client jq
sudo usermod -aG libvirt,kvm $USER
exit
```

## 2. Репозиторий, ключи и секреты

```bash
git clone https://github.com/ivesselov/devops-lab1.git ~/lab
cd ~/lab

# SSH-ключ пользователя ansible (каталог keys/ в .gitignore)
mkdir -p keys
ssh-keygen -t ed25519 -N "" -C ansible -f keys/ansible_ed25519

# пароли стенда (ansible/secrets.yml в .gitignore)
cp ansible/secrets.example.yml ansible/secrets.yml
ansible/secrets.yml   # задать пароли
```

## 3. Виртуальные машины

```bash
export VAGRANT_DEFAULT_PROVIDER=libvirt
vagrant up
vagrant status
```

Vagrant создаёт etcd01, pgsql01, pgsql02, k3s01 в сети 192.168.56.0/24,
пробрасывает порты на localhost хоста (5432, 6432, 7432, 80, 443), выставляет
MTU 1460 на eth1, создаёт пользователя `ansible` с ключом и sudo, ставит Ansible
на k3s01 и синхронизирует репозиторий в `/home/ansible/lab`. Изменения в репозитории 
применяются на k3s01 командой `vagrant rsync k3s01`

## 4. Проверка Ansible

```bash
vagrant ssh k3s01
sudo -iu ansible
cd ~/lab/ansible
ansible all -m ping
```

## 5. PostgreSQL HA-кластер

На k3s01 из `~/lab/ansible` по порядку:

```bash
ansible-playbook etcd.yml       
ansible-playbook patroni.yml    
ansible-playbook haproxy.yml    
ansible-playbook db.yml         
```

## 6. Kubernetes и мониторинг

```bash
ansible-playbook k3s.yml            
ansible-playbook node_exporter.yml  
ansible-playbook monitoring.yml     
```

Версия ingress-nginx задаётся переменной `ingress_nginx_version` в `k3s.yml`.

## 7. Разрешение имён на хосте

```bash
echo "127.0.0.1 prometheus.lab.local grafana.lab.local" | sudo tee -a /etc/hosts
```

## 8. Проверка

На хосте Vagrant:

```bash
# Patroni: Leader + Replica (streaming)
vagrant ssh pgsql01 -c "sudo /usr/local/bin/patronictl -c /etc/patroni/patroni.yml list"

# PostgreSQL через HAProxy (Primary) и напрямую к узлам
psql -h 127.0.0.1 -p 5432 -U postgres -c "select inet_server_addr(), pg_is_in_recovery()"
psql -h 127.0.0.1 -p 6432 -U postgres -c "select pg_is_in_recovery()"
psql -h 127.0.0.1 -p 7432 -U postgres -c "select pg_is_in_recovery()"

# Prometheus и Grafana по HTTPS
curl -sk https://prometheus.lab.local/-/ready
curl -sk https://grafana.lab.local/api/health

# все targets в состоянии up
curl -sk https://prometheus.lab.local/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.labels.instance)\t\(.health)"'
```



## Проверка отказоустойчивости

Контролируемый отказ Primary: `systemctl stop patroni` на pgsql01.

- Patroni назначил Primary узел pgsql02 (таймлайн 4 → 5);
- HAProxy перевёл трафик на pgsql02, подключение через `localhost:5432`
  продолжило работать без изменения строки подключения;
- после запуска Patroni pgsql01 вернулся в кластер репликой (`streaming`, лаг 0);
- записи, сделанные до отказа, после переключения и после восстановления,
  видны на восстановленном узле.

Результаты:
[до отказа](docs/failover/01_before.txt) ·
[после переключения](docs/failover/02_after_failover.txt) ·
[состояние HAProxy](docs/failover/02_haproxy.txt) ·
[после восстановления](docs/failover/03_after_recovery.txt) ·
[проверка репликации](docs/failover/04_replication_check.txt)

Прочие проверки: [targets Prometheus](docs/targets_up.txt) ·
[сохранность данных Prometheus и Grafana](docs/persistence-check.txt) ·
[дашборд узлов](docs/nodes.png) · [дашборд PostgreSQL](docs/postgresql.png)
