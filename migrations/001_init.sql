-- Migration: Create hotel_bookings and booking_events tables

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id        UUID NOT NULL,
    hotel_id      VARCHAR(100) NOT NULL,
    city          VARCHAR(100) NOT NULL,
    checkin_date  DATE NOT NULL,
    checkout_date DATE NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL,
    status        VARCHAR(50) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL PRIMARY KEY,
    booking_id UUID NOT NULL REFERENCES hotel_bookings(id),
    event_type VARCHAR(100) NOT NULL,
    payload    JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Index to optimize the aggregation query:
-- SELECT org_id, status, COUNT(*), SUM(amount)
-- FROM hotel_bookings
-- WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days'
-- GROUP BY org_id, status;
--
-- Composite index on (city, created_at) supports the WHERE filter efficiently.
-- Including org_id and status as covering columns avoids heap lookups during GROUP BY.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);
