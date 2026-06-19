#!/bin/bash
# Database backup script

# Check if arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <database_name> <database_host>"
    exit 1
fi

DB_NAME=$1
DB_HOST=$2
BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${DATE}.sql.gz"

# Ensure backup directory exists
mkdir -p ${BACKUP_DIR}

# Perform backup
echo "Backing up database ${DB_NAME} from ${DB_HOST}..."
pg_dump -h ${DB_HOST} ${DB_NAME} | gzip > ${BACKUP_FILE}

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup completed successfully: ${BACKUP_FILE}"
    
    # Remove backups older than 14 days
    find ${BACKUP_DIR} -name "${DB_NAME}_*.sql.gz" -type f -mtime +14 -delete
    
    exit 0
else
    echo "Backup failed!"
    exit 1
fi