
#!/bin/bash
set -e

echo "=== АВАРИЙНОЕ ВОССТАНОВЛЕНИЕ BACKEND-2 (ЛОГИРОВАНИЕ) ==="
echo "Время начала: $(date)"

# Конфигурационные переменные
GIT_REPO="https://github.com/your-username/your-infrastructure-repo.git"
MYSQL_MASTER="192.168.1.20"
NEW_SERVER_IP="192.168.1.22"
BACKUP_SERVER="user@backup-server.com"
LOGSTASH_SERVER="192.168.1.30"  # Сервер Logstash/ELK

# Логирование
LOG_FILE="/var/log/disaster-recovery-backend2.log"
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
ufw allow 9100  # Node Exporter
ufw --force enable

echo "4. Настройка Apache..."
a2enmod rewrite
a2enmod remoteip

# Копирование конфига Apache
cp /tmp/infrastructure/backend-server-2/apache/my-site-backend.conf /etc/apache2/sites-available/
a2ensite my-site-backend.conf

# Настройка Apache на порту 8080
sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf

echo "5. Восстановление файлов WordPress..."
rsync -avz $BACKUP_SERVER:/backups/wordpress/latest/ /var/www/html/wordpress/

# Настройка прав
chown -R www-data:www-data /var/www/html/wordpress
find /var/www/html/wordpress -type d -exec chmod 755 {} \;
find /var/www/html/wordpress -type f -exec chmod 644 {} \;

echo "6. Настройка системы логирования (Filebeat)..."

# Установка Filebeat
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list
apt-get update
apt-get install -y filebeat

# Копирование конфига Filebeat
cp /tmp/infrastructure/backend-server-2/logging/filebeat.yml /etc/filebeat/

# Включение модулей Apache
filebeat modules enable apache

echo "7. Настройка мониторинга (Node Exporter, Apache Exporter)..."

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

echo "8. Настройка бэкапа базы данных (Slave репликация)..."

# Установка MySQL Slave
apt-get install -y mysql-server

# Остановка MySQL для настройки
systemctl stop mysql

# Копирование конфига Slave
cp /tmp/infrastructure/database/slave/my.cnf /etc/mysql/mysql.conf.d/replication.cnf

# Запуск MySQL
systemctl start mysql

echo "9. Настройка репликации..."
# Получение данных для настройки репликации из бэкапа
MASTER_INFO=$(ssh $BACKUP_SERVER "cat /backups/mysql/latest/slave_status.txt")

MASTER_LOG_FILE=$(echo "$MASTER_INFO" | grep "Master_Log_File" | awk '{print $2}')
MASTER_LOG_POS=$(echo "$MASTER_INFO" | grep "Read_Master_Log_Pos" | awk '{print $2}')

if [ -z "$MASTER_LOG_FILE" ] || [ -z "$MASTER_LOG_POS" ]; then
    echo "Не удалось получить позицию репликации из бэкапа"
    echo "Настройте репликацию вручную:"
    echo "CHANGE MASTER TO MASTER_HOST='$MYSQL_MASTER', MASTER_USER='replicator', MASTER_PASSWORD='password', MASTER_LOG_FILE='mysql-bin.000001', MASTER_LOG_POS=107;"
else
    mysql -e "CHANGE MASTER TO MASTER_HOST='$MYSQL_MASTER', MASTER_USER='replicator', MASTER_PASSWORD='password', MASTER_LOG_FILE='$MASTER_LOG_FILE', MASTER_LOG_POS=$MASTER_LOG_POS;"
    mysql -e "START SLAVE;"
    echo "Репликация настроена с позиции: $MASTER_LOG_FILE:$MASTER_LOG_POS"
fi

echo "10. Настройка скрипта бэкапа..."
cp /tmp/infrastructure/database/scripts/db-backup.sh /opt/scripts/
chmod +x /opt/scripts/db-backup.sh

# Добавление в cron
echo "0 2 * * * /opt/scripts/db-backup.sh" | crontab -

echo "11. Запуск сервисов..."
systemctl daemon-reload
systemctl enable apache2 node_exporter apache_exporter filebeat mysql
systemctl start apache2 node_exporter apache_exporter filebeat mysql

# Запуск Filebeat после небольшой задержки
sleep 10
systemctl start filebeat

echo "12. Проверка работы сервисов..."
services=("apache2" "node_exporter" "apache_exporter" "filebeat" "mysql")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service работает нормально"
    else
        echo "✗ $service не запустился"
        systemctl status $service
    fi
done

echo "13. Проверка репликации..."
SLAVE_STATUS=$(mysql -e "SHOW SLAVE STATUS\G")
if echo "$SLAVE_STATUS" | grep -q "Slave_IO_Running: Yes" && echo "$SLAVE_STATUS" | grep -q "Slave_SQL_Running: Yes"; then
    echo "✓ Репликация работает нормально"
else
    echo "✗ Проблемы с репликацией"
    echo "$SLAVE_STATUS"
fi

echo "14. Обновление конфига Nginx на фронтенде..."
echo "ВАЖНО: Обновите IP бэкенда в конфиге Nginx на фронтенд сервере:"
echo "Замените старый IP на $NEW_SERVER_IP в /etc/nginx/sites-available/my-site.conf"
echo "И выполните: nginx -t && systemctl reload nginx"

echo "15. Тестирование приложения..."
if curl -s http://localhost:8080 > /dev/null; then
    echo "✓ Backend-2 доступен на порту 8080"
else
    echo "✗ Backend-2 не доступен на порту 8080"
fi

echo "=== ВОССТАНОВЛЕНИЕ BACKEND-2 ЗАВЕРШЕНО ==="
echo "Время завершения: $(date)"
echo "Лог сохранен в: $LOG_FILE"
