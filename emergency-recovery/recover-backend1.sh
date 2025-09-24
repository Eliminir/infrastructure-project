#!/bin/bash
set -e

echo "=== АВАРИЙНОЕ ВОССТАНОВЛЕНИЕ BACKEND-1 (МОНИТОРИНГ) ==="
echo "Время начала: $(date)"

# Конфигурационные переменные
GIT_REPO="https://github.com/your-username/your-infrastructure-repo.git"
MYSQL_MASTER="192.168.1.20"
NEW_SERVER_IP="192.168.1.21"
BACKUP_SERVER="user@backup-server.com"

# Логирование
LOG_FILE="/var/log/disaster-recovery-backend1.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "1. Обновление системы и установка базовых пакетов..."
apt-get update
apt-get install -y git curl wget apache2 php php-mysql libapache2-mod-php ufw

echo "2. Клонирование репозитория с конфигами..."
cd /tmp
if [ -d "infrastructure" ]; then
    rm -rf infrastructure
fi
git clone $GIT_REPO infrastructure

echo "3. Настройка firewall..."
ufw allow ssh
ufw allow 8080  # Apache backend port
ufw allow 9090  # Prometheus
ufw allow 9100  # Node Exporter
ufw --force enable

echo "4. Настройка Apache..."
a2enmod rewrite
a2enmod remoteip

# Копирование конфига Apache
cp /tmp/infrastructure/backend-server-1/apache/my-site-backend.conf /etc/apache2/sites-available/
a2ensite my-site-backend.conf

# Настройка Apache на порту 8080
sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf

echo "5. Восстановление файлов WordPress..."
rsync -avz $BACKUP_SERVER:/backups/wordpress/latest/ /var/www/html/wordpress/

# Настройка прав
chown -R www-data:www-data /var/www/html/wordpress
find /var/www/html/wordpress -type d -exec chmod 755 {} \;
find /var/www/html/wordpress -type f -exec chmod 644 {} \;

echo "6. Настройка мониторинга (Prometheus, Node Exporter, Apache Exporter)..."

# Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
useradd -rs /bin/false node_exporter

cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Apache Exporter
wget https://github.com/Lusitaniae/apache_exporter/releases/download/v0.13.0/apache_exporter-0.13.0.linux-amd64.tar.gz
tar xzf apache_exporter-0.13.0.linux-amd64.tar.gz
cp apache_exporter-0.13.0.linux-amd64/apache_exporter /usr/local/bin/

cat <<EOF > /etc/systemd/system/apache_exporter.service
[Unit]
Description=Apache Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/apache_exporter --scrape_uri=http://localhost:8080/server-status?auto

[Install]
WantedBy=multi-user.target
EOF

# Prometheus
useradd --no-create-home --shell /bin/false prometheus
mkdir /etc/prometheus /var/lib/prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.47.0/prometheus-2.47.0.linux-amd64.tar.gz
tar xzf prometheus-2.47.0.linux-amd64.tar.gz
cp prometheus-2.47.0.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.47.0.linux-amd64/promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool

# Копирование конфига Prometheus
cp /tmp/infrastructure/backend-server-1/monitoring/prometheus.yml /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus

# Восстановление данных Prometheus (если есть бэкап)
if rsync -avz $BACKUP_SERVER:/backups/prometheus/data/ /var/lib/prometheus/; then
    echo "✓ Данные Prometheus восстановлены"
else
    echo "i Данные Prometheus не восстановлены, будет создана новая БД"
    mkdir -p /var/lib/prometheus/data
fi

chown -R prometheus:prometheus /var/lib/prometheus

cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/data \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

echo "7. Запуск сервисов..."
systemctl daemon-reload
systemctl enable apache2 node_exporter apache_exporter prometheus
systemctl start apache2 node_exporter apache_exporter prometheus

echo "8. Проверка работы сервисов..."
services=("apache2" "node_exporter" "apache_exporter" "prometheus")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service работает нормально"
    else
        echo "✗ $service не запустился"
        systemctl status $service
    fi
done

echo "9. Обновление конфига Nginx на фронтенде..."
echo "ВАЖНО: Обновите IP бэкенда в конфиге Nginx на фронтенд сервере:"
echo "Замените старый IP на $NEW_SERVER_IP в /etc/nginx/sites-available/my-site.conf"
echo "И выполните: nginx -t && systemctl reload nginx"

echo "10. Тестирование приложения..."
if curl -s http://localhost:8080 > /dev/null; then
    echo "✓ Backend-1 доступен на порту 8080"
else
    echo "✗ Backend-1 не доступен на порту 8080"
fi

echo "=== ВОССТАНОВЛЕНИЕ BACKEND-1 ЗАВЕРШЕНО ==="
echo "Время завершения: $(date)"
echo "Лог сохранен в: $LOG_FILE"
