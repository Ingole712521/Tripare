#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

section() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

section "1. TERRAFORM FMT"
cd "$PROJECT_DIR/infra/envs/dev"
terraform fmt -recursive ../../
echo "Format check: PASSED"

section "2. TERRAFORM INIT + VALIDATE (dev)"
terraform init -no-color | tail -3
terraform validate

section "3. TERRAFORM PLAN (dev)"
terraform plan -refresh=false -var-file=terraform.tfvars -no-color | tail -15

section "4. TERRAFORM PLAN (prod)"
cd "$PROJECT_DIR/infra/envs/prod"
terraform init -no-color | tail -3
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars -no-color | tail -10

section "5. DOCKER COMPOSE UP"
cd "$PROJECT_DIR"
docker compose up -d

section "6. DOCKER PS"
docker ps --filter name=hotel-booking

section "7. DATABASE TABLES"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "\dt"

section "8. SEED DATA COUNTS"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c \
  "SELECT COUNT(*) AS hotel_bookings FROM hotel_bookings;" \
  -c "SELECT COUNT(*) AS booking_events FROM booking_events;" \
  -c "SELECT DISTINCT city FROM hotel_bookings ORDER BY city;" \
  -c "SELECT DISTINCT status FROM hotel_bookings ORDER BY status;"

section "9. QUERY OPTIMIZATION"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c \
  "EXPLAIN ANALYZE SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status;"

section "10. BACKUP"
"$SCRIPT_DIR/backup.sh"

section "11. RESTORE + VERIFY"
"$SCRIPT_DIR/restore.sh"
echo "Original DB bookings:"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -t -c "SELECT COUNT(*) FROM hotel_bookings;"
echo "Restored DB bookings:"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb_restored -t -c "SELECT COUNT(*) FROM hotel_bookings;"

section "ALL CHECKS COMPLETE"
echo "GitHub repo: https://github.com/Ingole712521/Tripare"
