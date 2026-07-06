#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"

POSTGRES_USER="${POSTGRES_USER:-hoteladmin}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-hotelpass}"
POSTGRES_DB="${POSTGRES_DB:-hoteldb}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
CONTAINER_NAME="${CONTAINER_NAME:-hotel-booking-db}"
RESTORE_DB="${RESTORE_DB:-hoteldb_restored}"

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE="$(ls -t "$BACKUP_DIR"/hoteldb_*.sql 2>/dev/null | head -1 || true)"
fi

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    echo "Usage: $0 [backup_file.sql]"
    echo "No backup file found in $BACKUP_DIR"
    exit 1
fi

echo "Restoring from backup: $BACKUP_FILE"
echo "Target database: $RESTORE_DB"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" \
        psql -U "$POSTGRES_USER" -d postgres -tc \
        "SELECT 1 FROM pg_database WHERE datname = '$RESTORE_DB'" | grep -q 1 \
        || docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" \
            psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $RESTORE_DB;"

    docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" \
        psql -U "$POSTGRES_USER" -d "$RESTORE_DB" < "$BACKUP_FILE"
else
    export PGPASSWORD="$POSTGRES_PASSWORD"
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -tc \
        "SELECT 1 FROM pg_database WHERE datname = '$RESTORE_DB'" | grep -q 1 \
        || psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
            -c "CREATE DATABASE $RESTORE_DB;"

    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$RESTORE_DB" < "$BACKUP_FILE"
fi

echo ""
echo "Restore completed successfully into database: $RESTORE_DB"
echo ""
echo "Verification queries:"
echo "  SELECT COUNT(*) FROM hotel_bookings;"
echo "  SELECT COUNT(*) FROM booking_events;"
echo "  SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings"
echo "    WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'"
echo "    GROUP BY org_id, status;"
