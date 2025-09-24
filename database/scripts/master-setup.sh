
#!/bin/bash
# ... (установка MySQL)
systemctl restart mysql

# Создание пользователя для репликации
mysql -e "CREATE USER 'replicator'@'%' IDENTIFIED BY 'strong_password';"
mysql -e "GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';"
mysql -e "FLUSH PRIVILEGES;"

# Бэкап БД для переноса на Slave
mysqldump -u root -p wordpress_db > /tmp/wordpress_db.sql
echo "Скопируйте дамп на Slave сервер и выполните настройку."
