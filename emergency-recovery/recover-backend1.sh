#!/bin/bash
# Этот скрипт выполняется на НОВОМ сервере для замены backend-1

NEW_SERVER_IP="192.168.1.100"
GIT_REPO="https://github.com/your-username/your-repo.git"

echo "Начало аварийного восстановления Backend-1..."

# Установка базовых пакетов и Git
apt update && apt install -y git

# Клонирование репозитория с конфигами
git clone $GIT_REPO /tmp/iac

# Запуск скрипта первоначальной настройки бэкенда-1
/tmp/iac/backend-server-1/scripts/backend1-setup.sh

# Восстановление данных мониторинга (если нужно)
# rsync -avz user@backup-server:/opt/monitoring-data/ /opt/prometheus/data/

# Регистрация в Prometheus (если IP изменился) - нужно обновить конфиг Prometheus
echo "Сервер $NEW_SERVER_IP восстановлен. Не забудьте обновить targets в Prometheus!"

echo "Восстановление Backend-1 завершено."
