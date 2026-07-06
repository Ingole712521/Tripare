# DevOps Assessment: Terraform + Database Reliability

This repository contains a complete solution for the DevOps assessment covering AWS infrastructure design with Terraform and local database reliability tasks (backup, restore, and query optimization).

## Repository Structure

```
.
├── infra/
│   ├── modules/
│   │   ├── network/     # VPC, subnets, NAT, route tables
│   │   ├── ecs/         # ALB, ECS cluster, Fargate service, security groups
│   │   └── rds/         # RDS PostgreSQL, security group (ECS-only access)
│   └── envs/
│       ├── dev/         # Smaller instances, short backup retention
│       └── prod/        # Larger instances, deletion protection enabled
├── migrations/          # SQL schema migrations
├── scripts/
│   ├── seed.sql         # Seed data (120 bookings)
│   ├── backup.sh        # Timestamped pg_dump backup
│   └── restore.sh       # Restore into fresh database
├── docker-compose.yml   # Local PostgreSQL
└── .github/workflows/   # Terraform CI on pull requests
```

## Architecture (Terraform)

```
Internet → ALB (public subnets) → ECS/Fargate (private subnets) → RDS (private subnets)
```

- **VPC**: Public and private subnets across 2 AZs
- **ALB**: Internet-facing, HTTP on port 80
- **ECS/Fargate**: Nginx placeholder container in private subnets
- **RDS**: PostgreSQL 15 in private subnets, accessible only from ECS security group

### Environment Differences

| Setting | dev | prod |
|---------|-----|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| ECS CPU/Memory | 256/512 | 512/1024 |
| ECS desired count | 1 | 2 |
| RDS instance | db.t3.micro | db.t3.small |
| Storage | 20 GB | 50 GB |
| Backup retention | 3 days | 30 days |
| Deletion protection | false | true |
| Multi-AZ | false | true |

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- [Terraform](https://www.terraform.io/downloads) >= 1.5.0 (for infrastructure validation)
- Bash shell (Git Bash on Windows)

## Reviewer Verification (exact commands)

Run from the repository root unless noted.

### Terraform (dev)

```bash
cd infra/envs/dev
terraform fmt -recursive ../../
terraform init
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars
```

Expected: `Success! The configuration is valid.` and `Plan: 28 to add, 0 to change, 0 to destroy.`

Repeat the same commands in `infra/envs/prod`.

### Database

```bash
docker compose up -d
./scripts/backup.sh
./scripts/restore.sh
```

Verify restore:

```bash
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -t -c "SELECT COUNT(*) FROM hotel_bookings;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb_restored -t -c "SELECT COUNT(*) FROM hotel_bookings;"
```

Expected: both counts match.

### Run all checks at once

```bash
chmod +x scripts/verify-all.sh
./scripts/verify-all.sh
```

## Part 1-3: Terraform

### Validate Locally (no AWS deployment required)

```bash
cd infra/envs/dev

# Format check
terraform fmt -recursive ../../

# Initialize
terraform init

# Validate configuration
terraform validate

# Review plan (plan-only, no apply)
terraform plan -refresh=false -var-file=terraform.tfvars
```

Repeat for `infra/envs/prod`.

### Backend Configuration

Each environment has its own local state file (separate state per environment):
- `dev`: `infra/envs/dev/terraform.tfstate`
- `prod`: `infra/envs/prod/terraform.tfstate`

For production use, replace the `backend "local"` block in each `backend.tf` with an S3 backend:

```hcl
terraform {
  backend "s3" {
    bucket         = "hotel-booking-terraform-state"
    key            = "dev/terraform.tfstate"  # or prod/terraform.tfstate
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hotel-booking-terraform-locks"
  }
}
```

### GitHub Actions

On pull requests touching `infra/**`, the workflow runs:
1. `terraform fmt -check`
2. `terraform init -backend=false`
3. `terraform validate`
4. `terraform plan -refresh=false`

Plan output is posted as a PR comment and saved as a workflow artifact.

## Part 4-6: Local Database

### Start Database

```bash
docker compose up -d
```

This starts PostgreSQL 15 and runs `migrations/001_init.sql` automatically.

### Load Seed Data

```bash
docker exec -i hotel-booking-db psql -U hoteladmin -d hoteldb < scripts/seed.sql
```

### Verify Tables and Data

```bash
docker exec -it hotel-booking-db psql -U hoteladmin -d hoteldb
```

```sql
SELECT COUNT(*) FROM hotel_bookings;   -- expect 120
SELECT COUNT(*) FROM booking_events;   -- expect 70+
SELECT DISTINCT city FROM hotel_bookings;
SELECT DISTINCT status FROM hotel_bookings;
```

### Query Optimization

Target query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

**Index added** (`migrations/001_init.sql`):

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);
```

**Why this index:**
- `city` is the equality filter — leading column enables fast lookup
- `created_at DESC` supports the range condition (`>= NOW() - 30 days`)
- `INCLUDE (org_id, status, amount)` makes this a covering index for the `GROUP BY` and `SUM(amount)`, avoiding heap fetches

Verify index usage:

```sql
EXPLAIN ANALYZE
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Look for `Index Only Scan` or `Bitmap Index Scan` on `idx_hotel_bookings_city_created_at`.

### Backup

```bash
chmod +x scripts/backup.sh scripts/restore.sh
./scripts/backup.sh
```

Creates a timestamped dump in `backups/hoteldb_YYYYMMDD_HHMMSS.sql`.

### Restore

```bash
./scripts/restore.sh
# Or specify a backup file:
./scripts/restore.sh backups/hoteldb_20260101_120000.sql
```

Restores into a fresh database `hoteldb_restored` by default.

### Verify Restore Worked

```bash
docker exec -it hotel-booking-db psql -U hoteladmin -d hoteldb_restored -c "SELECT COUNT(*) FROM hotel_bookings;"
docker exec -it hotel-booking-db psql -U hoteladmin -d hoteldb_restored -c "SELECT COUNT(*) FROM booking_events;"
```

Compare counts with the original `hoteldb` database — they should match.

```bash
# Original
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -t -c "SELECT COUNT(*) FROM hotel_bookings;"

# Restored
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb_restored -t -c "SELECT COUNT(*) FROM hotel_bookings;"
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | hoteladmin | Database user |
| `POSTGRES_PASSWORD` | hotelpass | Database password |
| `POSTGRES_DB` | hoteldb | Database name |
| `POSTGRES_PORT` | 5432 | Host port |
| `RESTORE_DB` | hoteldb_restored | Target DB for restore |
| `BACKUP_DIR` | ./backups | Backup output directory |

## Cleanup

```bash
docker compose down -v
```

## Submission Checklist

- [x] Terraform infrastructure code (VPC, ALB, ECS, RDS)
- [x] dev and prod environment examples
- [x] Docker Compose database setup
- [x] SQL migration files
- [x] Seed data script (120 bookings)
- [x] Database backup script
- [x] Database restore script
- [x] README with setup and verification steps
- [x] GitHub Actions workflow for Terraform PR validation
# Tripare
