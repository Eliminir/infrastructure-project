
#!/bin/bash
set -e

echo "=== АВАРИЙНОЕ ВОССТАНОВЛЕНИЕ FRONTEND СЕРВЕРА ==="
echo "Время начала: $(date)"

# Конфигурационные переменные
GIT_REPO="https://github.com/your-username/your-infrastructure-repo.git"
BACKUP_SERVER="user@backup-server.com"
NEW_SERVER_IP="192.168.1.10"  # Новый IP сервера
DOMAIN="your-domain.com"

# Логирование
LOG_FILE="/var/log/disaster-recovery-frontend.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "1. Обновление системы и установка базовых пакетов..."
apt-get update
apt-get install -y git curl wget ufw nginx

echo "2. Клонирование репозитория с конфигами..."
cd /tmp
if [ -d "infrastructure" ]; then
    rm -rf infrastructure
fi
git clone $GIT_REPO infrastructure

echo "3. Настройка firewall..."
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

echo "4. Копирование конфигурационных файлов Nginx..."
cp -r /tmp/infrastructure/frontend-server/* /etc/nginx/

# Обновление IP бэкендов в конфиге (если нужно)
sed -i 's/backend-server-1-old-ip/192.168.1.21/g' /etc/nginx/sites-available/my-site.conf
sed -i 's/backend-server-2-old-ip/192.168.1.22/g' /etc/nginx/sites-available/my-site.conf

echo "5. Проверка конфигурации Nginx..."
nginx -t

echo "6. Включение и запуск Nginx..."
systemctl enable nginx
systemctl start nginx

echo "7. Настройка мониторинга (Node Exporter)..."
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
useradd -rs /bin/false node_exporter

# Создание systemd service для node_exporter
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

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

echo "8. Настройка cron для автоматических обновлений..."
echo "0 3 * * 6 apt-get update && apt-get upgrade -y" | crontab -

echo "9. Проверка работы сервисов..."
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx работает нормально"
else
    echo "✗ Nginx не запустился"
    exit 1
fi

if systemctl is-active --quiet node_exporter; then
    echo "✓ Node Exporter работает нормально"
else
    echo "✗ Node Exporter не запустился"
fi

echo "10. Тестирование доступности сайта..."
if curl -s -I http://localhost > /dev/null; then
    echo "✓ Сайт доступен локально"
else
    echo "✗ Сайт не доступен локально"
fi

echo "11. Обновление DNS записей (ручной шаг)..."
echo "ВАЖНО: Не забудьте обновить DNS запись для $DOMAIN на IP $NEW_SERVER_IP"

echo "12. Уведомление мониторинга..."
# Отправка уведомления в мониторинг (пример для Telegram)
# curl -s -X POST "https://api.telegram.org/bot<token>/sendMessage" \
#     -d chat_id=<chat_id> \
#     -d text="Frontend сервер восстановлен. Новый IP: $NEW_SERVER_IP"

echo "=== ВОССТАНОВЛЕНИЕ FRONTEND ЗАВЕРШЕНО ==="
echo "Время завершения: $(date)"
echo "Лог сохранен в: $LOG_FILE"
