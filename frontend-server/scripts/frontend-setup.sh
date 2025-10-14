#!/bin/bash
set -e # Выход при ошибке

echo "Установка Nginx..."
apt update && apt install -y nginx

echo "Копирование конфигурационных файлов..."
cp nginx.conf /etc/nginx/nginx.conf
cp sites-available/my-site.conf /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/my-site.conf /etc/nginx/sites-enabled/

echo "Проверка конфигурации..."
nginx -t

echo "Перезапуск Nginx..."
systemctl enable nginx
systemctl restart nginx

echo "Установка завершена!"
