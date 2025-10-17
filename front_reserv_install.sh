  GNU nano 7.2                                     front_reserv_install.sh
#!/bin/bash
set -e

REPO_URL="https://github.com/Eliminir/infrastructure-project/"


echo "Установка NGINX..."
apt-get update && apt-get install -y nginx git

echo "Остановка NGINX и загрузка конфигов..."
systemctl stop nginx
git clone "$REPO_URL" /tmp/nginx-configs
cp -r /tmp/nginx-configs/* /etc/nginx/

nginx -t
systemctl start nginx
rm -rf /tmp/nginx-configs

echo "Готово! NGINX запущен на адресе: $IP_ADDRESS"


