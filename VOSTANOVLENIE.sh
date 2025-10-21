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

sudo cat > /etc/filebeat/filebeat.yml << 'EOF'
###################### Filebeat Configuration Example #########################

# ============================== Filebeat inputs ===============================

filebeat.inputs:
- type: filestream
  id: nginx-logs
  enabled: true
  paths:
    - /var/log/nginx/*.log
  exclude_files: ['.gz$']

- type: filestream
  id: system-logs
  enabled: true
  paths:
    - /var/log/*.log
    - /var/log/syslog
    - /var/log/auth.log

# ============================== Filebeat modules ==============================

filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: true
  reload.period: 10s

# ============================== Filebeat output ===============================

output.elasticsearch:
  hosts: ["192.168.196.130:9200"]
  username: "elastic"
  password: "123123"
  ssl.enabled: false

# ================================= Processors =================================
processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
EOF

echo "Проверка конфигурации..."
sudo filebeat test config

echo "Запуск Filebeat..."
sudo systemctl daemon-reload
sudo systemctl enable filebeat
sudo systemctl restart filebeat

echo "Проверка статуса..."
sudo systemctl status filebeat --no-pager
sudo systemctl status nginx --no-pager
echo "Готово!
