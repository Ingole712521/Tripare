#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/hoteldb_${TIMESTAMP}.sql"

POSTGRES_USER="${POSTGRES_USER:-hoteladmin}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-hotelpass}"
POSTGRES_DB="${POSTGRES_DB:-hoteldb}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
CONTAINER_NAME="${CONTAINER_NAME:-hotel-booking-db}"

mkdir -p "$BACKUP_DIR"

echo "Creating backup: $BACKUP_FILE"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" \
        pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-acl \
        > "$BACKUP_FILE"
else
  export PGPASSWORD="$POSTGRES_PASSWORD"
  pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      --no-owner --no-acl > "$BACKUP_FILE"
fi

echo "Backup completed successfully: $BACKUP_FILE"
echo "File size: $(du -h "$BACKUP_FILE" | cut -f1)"
