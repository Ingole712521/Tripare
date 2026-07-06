DO $$
DECLARE
    org_ids UUID[] := ARRAY[
        'a1111111-1111-1111-1111-111111111111',
        'b2222222-2222-2222-2222-222222222222',
        'c3333333-3333-3333-3333-333333333333',
        'd4444444-4444-4444-4444-444444444444',
        'e5555555-5555-5555-5555-555555555555'
    ];
    cities TEXT[] := ARRAY['delhi', 'mumbai', 'bangalore', 'chennai', 'hyderabad', 'kolkata', 'pune', 'jaipur'];
    statuses TEXT[] := ARRAY['confirmed', 'pending', 'cancelled', 'completed', 'refunded'];
    event_types TEXT[] := ARRAY['booking_created', 'payment_received', 'checkin', 'checkout', 'cancellation', 'refund_processed'];
    i INT;
    booking_uuid UUID;
    selected_org UUID;
    selected_city TEXT;
    selected_status TEXT;
    checkin DATE;
    checkout DATE;
    booking_amount NUMERIC(12,2);
    days_ago INT;
BEGIN
    FOR i IN 1..120 LOOP
        selected_org := org_ids[1 + (i % array_length(org_ids, 1))];
        selected_city := cities[1 + (i % array_length(cities, 1))];
        selected_status := statuses[1 + (i % array_length(statuses, 1))];
        days_ago := (i % 60);
        checkin := CURRENT_DATE + (days_ago % 30);
        checkout := checkin + ((i % 5) + 1);
        booking_amount := ROUND((1500 + (i * 137.5) % 8500)::numeric, 2);

        booking_uuid := uuid_generate_v4();

        INSERT INTO hotel_bookings (id, org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
        VALUES (
            booking_uuid,
            selected_org,
            'HOTEL-' || LPAD((i % 25 + 1)::text, 3, '0'),
            selected_city,
            checkin,
            checkout,
            booking_amount,
            selected_status,
            NOW() - (days_ago || ' days')::interval
        );

        IF i % 10 < 7 THEN
            INSERT INTO booking_events (booking_id, event_type, payload, created_at)
            VALUES (
                booking_uuid,
                event_types[1 + (i % array_length(event_types, 1))],
                jsonb_build_object(
                    'source', 'seed_script',
                    'booking_index', i,
                    'amount', booking_amount,
                    'city', selected_city
                ),
                NOW() - (days_ago || ' days')::interval + interval '1 hour'
            );

            IF i % 3 = 0 THEN
                INSERT INTO booking_events (booking_id, event_type, payload, created_at)
                VALUES (
                    booking_uuid,
                    'payment_received',
                    jsonb_build_object('payment_method', 'card', 'amount', booking_amount),
                    NOW() - (days_ago || ' days')::interval + interval '2 hours'
                );
            END IF;
        END IF;
    END LOOP;
END $$;
