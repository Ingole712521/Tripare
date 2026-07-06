# DevOps Assessment: Terraform + Database Reliability

GitHub Repository: https://github.com/Ingole712521/Tripare

This project includes Terraform AWS infrastructure design, a local PostgreSQL database with Docker Compose, migrations, seed data, backup/restore scripts, and verification steps.

Actual AWS deployment is not required. Terraform is validated using `fmt`, `init`, `validate`, and `plan`. Database tasks run locally with Docker.

---

## What Is Implemented

| Requirement | Location |
|-------------|----------|
| Terraform infrastructure (VPC, ALB, ECS, RDS) | `infra/modules/` |
| dev environment | `infra/envs/dev/` |
| prod environment | `infra/envs/prod/` |
| Docker Compose database | `docker-compose.yml` |
| SQL migration | `migrations/001_init.sql` |
| Seed data script | `scripts/seed.sql` |
| Backup script | `scripts/backup.sh` |
| Restore script | `scripts/restore.sh` |
| Full verification script | `scripts/verify-all.sh` |
| GitHub Actions (Terraform CI) | `.github/workflows/terraform.yml` |

---

## Architecture

```
Internet → ALB (public subnets) → ECS/Fargate (private subnets) → RDS (private subnets)
```

- VPC with public and private subnets across 2 availability zones
- Application Load Balancer in public subnets
- ECS Fargate service with Nginx placeholder container in private subnets
- RDS PostgreSQL in private subnets, accessible only from ECS security group

### dev vs prod

| Setting | dev | prod |
|---------|-----|------|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| ECS CPU / Memory | 256 / 512 | 512 / 1024 |
| ECS task count | 1 | 2 |
| RDS instance | db.t3.micro | db.t3.small |
| Storage | 20 GB | 50 GB |
| Backup retention | 3 days | 30 days |
| Deletion protection | false | true |
| Multi-AZ | false | true |

---

## Prerequisites

1. Install [Docker Desktop](https://docs.docker.com/get-docker/) and start it
2. Install [Terraform](https://www.terraform.io/downloads) version 1.5.0 or higher
3. Install [Git](https://git-scm.com/)
4. Use Git Bash on Windows

---

## Step 1: Clone the Repository

```bash
git clone https://github.com/Ingole712521/Tripare.git
cd Tripare
```

If you already have the project folder locally:

```bash
cd "/d/Nehal/New folder/Assigment"
```

---

## Step 2: Terraform Review (dev)

Run Terraform from the environment folder. Do not run it from `infra/` or `infra/modules/`.

```bash
cd infra/envs/dev
terraform fmt -recursive ../../
terraform init
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars
```

Expected output:

- `Success! The configuration is valid.`
- `Plan: 28 to add, 0 to change, 0 to destroy.`

---

## Step 3: Terraform Review (prod)

```bash
cd ../prod
terraform fmt -recursive ../../
terraform init
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars
```

Expected output:

- `Success! The configuration is valid.`
- `Plan: 28 to add, 0 to change, 0 to destroy.`

---

## Step 4: Start Local Database

Go back to the project root:

```bash
cd ../../..
docker compose up -d
docker ps
```

Expected output:

- Container name: `hotel-booking-db`
- Status: `Up` and `healthy`
- Port: `5432`

The migration file `migrations/001_init.sql` runs automatically on first startup and creates:

- `hotel_bookings`
- `booking_events`
- index `idx_hotel_bookings_city_created_at`

---

## Step 5: Load Seed Data

```bash
docker exec -i hotel-booking-db psql -U hoteladmin -d hoteldb < scripts/seed.sql
```

This inserts:

- 120 hotel bookings
- booking events for many bookings
- multiple cities
- multiple organizations
- multiple booking statuses

---

## Step 6: Verify Tables and Data

```bash
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "\dt"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "SELECT COUNT(*) FROM hotel_bookings;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "SELECT COUNT(*) FROM booking_events;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "SELECT DISTINCT city FROM hotel_bookings ORDER BY city;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "SELECT DISTINCT status FROM hotel_bookings ORDER BY status;"
```

Expected:

- 2 tables visible
- at least 100 bookings
- multiple cities and statuses

---

## Step 7: Verify Query Optimization

Target query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Run:

```bash
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -c "EXPLAIN ANALYZE SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status;"
```

Index used:

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);
```

Why this index was chosen:

- `city` is the equality filter, so it is the leading column
- `created_at DESC` supports the date range filter
- `INCLUDE (org_id, status, amount)` allows the grouped query to read from the index efficiently

---

## Step 8: Backup Database

```bash
chmod +x scripts/backup.sh scripts/restore.sh
./scripts/backup.sh
ls backups/
```

Expected output:

- `Backup completed successfully`
- a timestamped file such as `backups/hoteldb_YYYYMMDD_HHMMSS.sql`

---

## Step 9: Restore Database

```bash
./scripts/restore.sh
```

Or restore a specific file:

```bash
./scripts/restore.sh backups/hoteldb_YYYYMMDD_HHMMSS.sql
```

The restore script:

- creates a fresh database named `hoteldb_restored`
- imports the latest backup if no file is provided

---

## Step 10: Verify Restore Worked

```bash
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -t -c "SELECT COUNT(*) FROM hotel_bookings;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb_restored -t -c "SELECT COUNT(*) FROM hotel_bookings;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb -t -c "SELECT COUNT(*) FROM booking_events;"
docker exec hotel-booking-db psql -U hoteladmin -d hoteldb_restored -t -c "SELECT COUNT(*) FROM booking_events;"
```

Expected:

- booking counts match
- event counts match

---

## Step 11: Run All Checks Together

```bash
chmod +x scripts/verify-all.sh
./scripts/verify-all.sh
```

This script runs:

1. Terraform fmt
2. Terraform init and validate for dev
3. Terraform plan for dev
4. Terraform plan for prod
5. Docker Compose startup
6. `docker ps`
7. table verification
8. seed data counts
9. query optimization check
10. backup
11. restore and count verification

---

## Reviewer Commands

These are the exact commands used for review.

### Terraform

```bash
cd infra/envs/dev
terraform fmt -recursive ../../
terraform init
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars
```

Repeat in `infra/envs/prod`.

### Database

```bash
docker compose up -d
./scripts/backup.sh
./scripts/restore.sh
```

---

## Backend State Configuration

Each environment has separate Terraform state:

- dev: `infra/envs/dev/terraform.tfstate`
- prod: `infra/envs/prod/terraform.tfstate`

For real AWS usage, replace the local backend in `backend.tf` with S3:

```hcl
terraform {
  backend "s3" {
    bucket         = "hotel-booking-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "hotel-booking-terraform-locks"
  }
}
```

Use `prod/terraform.tfstate` for the prod environment.

---

## GitHub Actions

Workflow file: `.github/workflows/terraform.yml`

On pull requests that change `infra/**`, GitHub Actions runs:

1. `terraform fmt -check -recursive ../../`
2. `terraform init`
3. `terraform validate`
4. `terraform plan -refresh=false -var-file=terraform.tfvars`

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| POSTGRES_USER | hoteladmin | Database user |
| POSTGRES_PASSWORD | hotelpass | Database password |
| POSTGRES_DB | hoteldb | Database name |
| POSTGRES_PORT | 5432 | Host port |
| RESTORE_DB | hoteldb_restored | Restore target database |
| BACKUP_DIR | ./backups | Backup output folder |

---

## Cleanup

```bash
docker compose down -v
```

---

## Submission Checklist

- [x] Terraform infrastructure code
- [x] dev and prod Terraform environment examples
- [x] Docker Compose database setup
- [x] SQL migration files
- [x] Seed data script
- [x] Database backup script
- [x] Database restore script
- [x] README with setup and verification steps
- [x] GitHub Actions workflow for Terraform validation

---

## Troubleshooting

### `No configuration files` during Terraform plan

You are in the wrong folder. Run Terraform from:

```bash
cd infra/envs/dev
```

not from `infra/`.

### Docker command fails

Start Docker Desktop and wait until it shows Running, then run:

```bash
docker compose up -d
```

### Restore fails on second run

Use the latest `scripts/restore.sh`. It drops and recreates `hoteldb_restored` before importing the backup.

### AWS Console is empty

This is expected. The assignment does not require `terraform apply`.
