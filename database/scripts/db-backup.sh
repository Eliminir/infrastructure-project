#!/bin/bash

# Конфигурация
BACKUP_DIR="/opt/backups/mysql"
MYSQL_USER="backup_user"
MYSQL_PASSWORD="backup_password"
MYSQL_HOST="localhost" # Бэкапим со Slave
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/db-backup.log"

# Создаем директорию для бэкапа
mkdir -p $BACKUP_DIR/$DATE

echo "$(date): Start backup" >> $LOG_FILE

# Получаем список таблиц
TABLES=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW TABLES FROM wordpress_db;" -s --skip-column-names)

# Бекапим каждую таблицу отдельно
for TABLE in $TABLES; do
    echo "Backing up table: $TABLE" >> $LOG_FILE
    mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD --single-transaction wordpress_db $TABLE > $BACKUP_DIR/$DATE/$TABLE.sql
done

# Получаем позицию бинарного лога на Slave (ЭТО ВАЖНО!)
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW SLAVE STATUS\G" > $BACKUP_DIR/$DATE/slave_status.txt

# Архивируем бэкап
tar -czf $BACKUP_DIR/wordpress_db_backup_$DATE.tar.gz -C $BACKUP_DIR $DATE

# Удаляем временные файлы
rm -rf $BACKUP_DIR/$DATE

# Удаляем старые бэкапы (храним 7 дней)
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "$(date): Backup completed: wordpress_db_backup_$DATE.tar.gz" >> $LOG_FILE
