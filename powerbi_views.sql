DROP VIEW IF EXISTS vw_executive_overview;

CREATE VIEW vw_executive_overview AS
SELECT
    "FlightDate"::date AS flight_date,
    "Month" AS month,
    "Reporting_Airline" AS airline,
    "OriginState" AS origin_state,
    "DestState" AS destination_state,

    COUNT(*) AS total_flights,

    COUNT(*) FILTER (
        WHERE "DepDel15" = 1
    ) AS delayed_departures,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE "DepDel15" = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS departure_delay_rate,

    ROUND(
        AVG("DepDelay") FILTER (
            WHERE "DepDelay" IS NOT NULL
        )::numeric,
        2
    ) AS avg_departure_delay,

    COUNT(*) FILTER (
        WHERE "Cancelled" = 1
    ) AS cancelled_flights,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE "Cancelled" = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS cancellation_rate,

    COUNT(*) FILTER (
        WHERE "Diverted" = 1
    ) AS diverted_flights,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE "Diverted" = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS diversion_rate

FROM flights_2025
GROUP BY
    "FlightDate"::date,
    "Month",
    "Reporting_Airline",
    "OriginState",
    "DestState";

SELECT *
FROM vw_executive_overview
LIMIT 10;

DROP VIEW IF EXISTS vw_delay_causes;

CREATE VIEW vw_delay_causes AS

SELECT
    'Carrier' AS delay_cause,
    SUM(COALESCE("CarrierDelay", 0)) AS attributed_delay_minutes

FROM flights_2025

UNION ALL

SELECT
    'Weather' AS delay_cause,
    SUM(COALESCE("WeatherDelay", 0)) AS attributed_delay_minutes

FROM flights_2025

UNION ALL

SELECT
    'NAS' AS delay_cause,
    SUM(COALESCE("NASDelay", 0)) AS attributed_delay_minutes

FROM flights_2025

UNION ALL

SELECT
    'Security' AS delay_cause,
    SUM(COALESCE("SecurityDelay", 0)) AS attributed_delay_minutes

FROM flights_2025

UNION ALL

SELECT
    'Late Aircraft' AS delay_cause,
    SUM(COALESCE("LateAircraftDelay", 0)) AS attributed_delay_minutes

FROM flights_2025;

SELECT *
FROM vw_delay_causes
ORDER BY attributed_delay_minutes DESC;

DROP VIEW IF EXISTS vw_recovery_summary;

CREATE VIEW vw_recovery_summary AS
SELECT
    "RecoveryStatus" AS recovery_status,

    COUNT(*) AS flight_count,

    ROUND(
        (
            100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
        )::numeric,
        2
    ) AS percentage_of_flights,

    ROUND(
        AVG("DelayRecovery")::numeric,
        2
    ) AS avg_delay_recovery_minutes

FROM flights_2025

GROUP BY
    "RecoveryStatus";

	SELECT *
FROM vw_recovery_summary
ORDER BY flight_count DESC;

DROP VIEW IF EXISTS vw_delay_causes_airline;

CREATE VIEW vw_delay_causes_airline AS

SELECT
    "Reporting_Airline" AS airline,

    SUM(COALESCE("CarrierDelay", 0)) AS carrier_delay_minutes,

    SUM(COALESCE("WeatherDelay", 0)) AS weather_delay_minutes,

    SUM(COALESCE("NASDelay", 0)) AS nas_delay_minutes,

    SUM(COALESCE("SecurityDelay", 0)) AS security_delay_minutes,

    SUM(COALESCE("LateAircraftDelay", 0)) AS late_aircraft_delay_minutes,

    SUM(
        COALESCE("CarrierDelay", 0)
        + COALESCE("WeatherDelay", 0)
        + COALESCE("NASDelay", 0)
        + COALESCE("SecurityDelay", 0)
        + COALESCE("LateAircraftDelay", 0)
    ) AS total_attributed_delay_minutes

FROM flights_2025

GROUP BY
    "Reporting_Airline";

	SELECT *
FROM vw_delay_causes_airline
ORDER BY total_attributed_delay_minutes DESC;

DROP VIEW IF EXISTS vw_propagation_summary;

CREATE VIEW vw_propagation_summary AS

SELECT
    CASE
        WHEN previous_arrival_delay IS NULL
            THEN 'No Previous Delay Data'
        WHEN previous_arrival_delay <= 0
            THEN 'On Time / Early'
        WHEN previous_arrival_delay <= 15
            THEN '1-15 min'
        WHEN previous_arrival_delay <= 30
            THEN '16-30 min'
        WHEN previous_arrival_delay <= 60
            THEN '31-60 min'
        WHEN previous_arrival_delay <= 120
            THEN '61-120 min'
        ELSE '120+ min'
    END AS previous_delay_bucket,

    COUNT(*) AS connections,

    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE departure_delayed_15 = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS next_flight_delay_rate

FROM aircraft_sequence_2025

WHERE is_valid_connection = TRUE

GROUP BY
    CASE
        WHEN previous_arrival_delay IS NULL
            THEN 'No Previous Delay Data'
        WHEN previous_arrival_delay <= 0
            THEN 'On Time / Early'
        WHEN previous_arrival_delay <= 15
            THEN '1-15 min'
        WHEN previous_arrival_delay <= 30
            THEN '16-30 min'
        WHEN previous_arrival_delay <= 60
            THEN '31-60 min'
        WHEN previous_arrival_delay <= 120
            THEN '61-120 min'
        ELSE '120+ min'
    END;

	SELECT *
FROM vw_propagation_summary;

DROP VIEW IF EXISTS vw_propagation_matrix;

CREATE VIEW vw_propagation_matrix AS

WITH categorized AS (

    SELECT
        previous_arrival_delay,

        CASE
            WHEN previous_arrival_delay IS NULL
                THEN 'No Previous Delay Data'
            WHEN previous_arrival_delay <= 0
                THEN 'On Time / Early'
            WHEN previous_arrival_delay <= 15
                THEN '1-15 min'
            WHEN previous_arrival_delay <= 30
                THEN '16-30 min'
            WHEN previous_arrival_delay <= 60
                THEN '31-60 min'
            WHEN previous_arrival_delay <= 120
                THEN '61-120 min'
            ELSE '120+ min'
        END AS previous_delay_bucket,

        CASE
            WHEN turnaround_minutes <= 30
                THEN '0-30 min'
            WHEN turnaround_minutes <= 60
                THEN '31-60 min'
            WHEN turnaround_minutes <= 90
                THEN '61-90 min'
            WHEN turnaround_minutes <= 120
                THEN '91-120 min'
            WHEN turnaround_minutes <= 180
                THEN '121-180 min'
            ELSE '180+ min'
        END AS turnaround_bucket,

        CASE
            WHEN previous_arrival_delay IS NULL
                THEN 0
            WHEN previous_arrival_delay <= 0
                THEN 1
            WHEN previous_arrival_delay <= 15
                THEN 2
            WHEN previous_arrival_delay <= 30
                THEN 3
            WHEN previous_arrival_delay <= 60
                THEN 4
            WHEN previous_arrival_delay <= 120
                THEN 5
            ELSE 6
        END AS previous_delay_sort,

        CASE
            WHEN turnaround_minutes <= 30
                THEN 1
            WHEN turnaround_minutes <= 60
                THEN 2
            WHEN turnaround_minutes <= 90
                THEN 3
            WHEN turnaround_minutes <= 120
                THEN 4
            WHEN turnaround_minutes <= 180
                THEN 5
            ELSE 6
        END AS turnaround_sort,

        departure_delayed_15

    FROM aircraft_sequence_2025

    WHERE
        is_valid_connection = TRUE
        AND turnaround_minutes IS NOT NULL
)

SELECT
    previous_delay_bucket,
    previous_delay_sort,
    turnaround_bucket,
    turnaround_sort,

    COUNT(*) AS connections,

    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE departure_delayed_15 = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS next_flight_delay_rate

FROM categorized

GROUP BY
    previous_delay_bucket,
    previous_delay_sort,
    turnaround_bucket,
    turnaround_sort;

	SELECT *
FROM vw_propagation_matrix
ORDER BY
    previous_delay_sort,
    turnaround_sort;

	DROP VIEW IF EXISTS vw_airline_propagation;

CREATE VIEW vw_airline_propagation AS

SELECT
    reporting_airline AS airline,

    COUNT(*) AS valid_connections,

    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE departure_delayed_15 = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS next_flight_delay_rate,

    COUNT(*) FILTER (
        WHERE previous_arrival_delay > 0
    ) AS connections_after_previous_delay,

    COUNT(*) FILTER (
        WHERE previous_arrival_delay > 0
          AND departure_delayed_15 = 1
    ) AS propagated_delays,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE previous_arrival_delay > 0
                  AND departure_delayed_15 = 1
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE previous_arrival_delay > 0
                ),
                0
            )
        )::numeric,
        2
    ) AS propagation_rate_after_previous_delay

FROM aircraft_sequence_2025

WHERE is_valid_connection = TRUE

GROUP BY
    reporting_airline

HAVING COUNT(*) >= 10000;

SELECT *
FROM vw_airline_propagation
ORDER BY propagation_rate_after_previous_delay DESC;


DROP VIEW IF EXISTS vw_high_risk_segments;

CREATE VIEW vw_high_risk_segments AS

WITH categorized AS (

    SELECT
        reporting_airline AS airline,

        CASE
            WHEN previous_arrival_delay IS NULL
                THEN 'No Previous Delay Data'
            WHEN previous_arrival_delay <= 0
                THEN 'On Time / Early'
            WHEN previous_arrival_delay <= 15
                THEN '1-15 min'
            WHEN previous_arrival_delay <= 30
                THEN '16-30 min'
            WHEN previous_arrival_delay <= 60
                THEN '31-60 min'
            WHEN previous_arrival_delay <= 120
                THEN '61-120 min'
            ELSE '120+ min'
        END AS previous_delay_bucket,

        CASE
            WHEN turnaround_minutes <= 30
                THEN '0-30 min'
            WHEN turnaround_minutes <= 60
                THEN '31-60 min'
            WHEN turnaround_minutes <= 90
                THEN '61-90 min'
            WHEN turnaround_minutes <= 120
                THEN '91-120 min'
            WHEN turnaround_minutes <= 180
                THEN '121-180 min'
            ELSE '180+ min'
        END AS turnaround_bucket,

        CASE
            WHEN previous_arrival_delay IS NULL
                THEN 0
            WHEN previous_arrival_delay <= 0
                THEN 1
            WHEN previous_arrival_delay <= 15
                THEN 2
            WHEN previous_arrival_delay <= 30
                THEN 3
            WHEN previous_arrival_delay <= 60
                THEN 4
            WHEN previous_arrival_delay <= 120
                THEN 5
            ELSE 6
        END AS previous_delay_sort,

        CASE
            WHEN turnaround_minutes <= 30
                THEN 1
            WHEN turnaround_minutes <= 60
                THEN 2
            WHEN turnaround_minutes <= 90
                THEN 3
            WHEN turnaround_minutes <= 120
                THEN 4
            WHEN turnaround_minutes <= 180
                THEN 5
            ELSE 6
        END AS turnaround_sort,

        departure_delayed_15

    FROM aircraft_sequence_2025

    WHERE
        is_valid_connection = TRUE
        AND turnaround_minutes IS NOT NULL
)

SELECT
    airline,
    previous_delay_bucket,
    previous_delay_sort,
    turnaround_bucket,
    turnaround_sort,

    COUNT(*) AS connections,

    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,

    ROUND(
        (
            100.0 * COUNT(*) FILTER (
                WHERE departure_delayed_15 = 1
            ) / NULLIF(COUNT(*), 0)
        )::numeric,
        2
    ) AS cascading_delay_rate

FROM categorized

GROUP BY
    airline,
    previous_delay_bucket,
    previous_delay_sort,
    turnaround_bucket,
    turnaround_sort

HAVING COUNT(*) >= 1000

ORDER BY
    cascading_delay_rate DESC,
    connections DESC;

	SELECT *
FROM vw_high_risk_segments
LIMIT 30;


SELECT
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'vw_delay_causes_airline',
      'vw_delay_causes',
      'vw_executive_overview',
      'vw_propagation_summary',
      'vw_propagation_matrix',
      'vw_airline_propagation',
      'vw_high_risk_segments',
      'vw_airport_delay_summary',
      'vw_route_delay_summary',
      'vw_recovery_summary'
  )
ORDER BY table_name, ordinal_position;

SELECT
    SUM(valid_connections) AS connections_analyzed,
    SUM(delayed_next_flights) AS delayed_next_flights,
    ROUND(
        100.0 * SUM(delayed_next_flights)
        / NULLIF(SUM(valid_connections), 0), 2
    ) AS next_flight_delay_rate
FROM public.vw_airline_propagation;

SELECT
    SUM(connections_after_previous_delay)
        AS connections_after_previous_delay,
    SUM(propagated_delays)
        AS propagated_delays,
    ROUND(
        100.0 * SUM(propagated_delays)
        / NULLIF(SUM(connections_after_previous_delay), 0),
        2
    ) AS propagation_rate
FROM public.vw_airline_propagation;

SELECT
    previous_delay_bucket,
    turnaround_bucket,
    connections,
    delayed_next_flights,
    next_flight_delay_rate
FROM public.vw_propagation_matrix
ORDER BY previous_delay_sort, turnaround_sort;

SELECT pg_get_viewdef(
    'public.vw_propagation_summary'::regclass,
    true
);

WITH view_sql AS (
    SELECT pg_get_viewdef(
        'public.vw_propagation_summary'::regclass,
        true
    ) AS definition
)
SELECT
    n AS chunk_number,
    SUBSTRING(definition FROM ((n - 1) * 1500 + 1) FOR 1500) AS sql_text
FROM view_sql
CROSS JOIN LATERAL generate_series(
    1,
    CEIL(LENGTH(definition)::numeric / 1500)::integer
) AS n
ORDER BY n;

SELECT
    previous_delay_bucket,
    SUM(connections) AS total_connections,
    SUM(delayed_next_flights) AS delayed_next_flights,
    ROUND(
        100.0 * SUM(delayed_next_flights)
        / NULLIF(SUM(connections), 0),
        2
    ) AS next_flight_delay_rate
FROM public.vw_propagation_summary
GROUP BY previous_delay_bucket
ORDER BY
    CASE previous_delay_bucket
        WHEN 'No Previous Delay Data' THEN 1
        WHEN 'On Time / Early' THEN 2
        WHEN '1-15 min' THEN 3
        WHEN '16-30 min' THEN 4
        WHEN '31-60 min' THEN 5
        WHEN '61-120 min' THEN 6
        WHEN '120+ min' THEN 7
        ELSE 8
    END;

	SELECT
    view_name,
    line_number,
    definition_line
FROM (
    SELECT
        'vw_propagation_summary' AS view_name,
        line_number,
        definition_line
    FROM regexp_split_to_table(
        pg_get_viewdef('public.vw_propagation_summary'::regclass, 80),
        E'\n'
    ) WITH ORDINALITY AS t(definition_line, line_number)

    UNION ALL

    SELECT
        'vw_propagation_matrix' AS view_name,
        line_number,
        definition_line
    FROM regexp_split_to_table(
        pg_get_viewdef('public.vw_propagation_matrix'::regclass, 80),
        E'\n'
    ) WITH ORDINALITY AS t(definition_line, line_number)
) AS view_definitions
ORDER BY view_name, line_number;

SELECT
    airline,
    COUNT(*) AS connections,
    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE departure_delayed_15 = 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS next_flight_delay_rate
FROM public.aircraft_sequence_2025
WHERE is_valid_connection = TRUE
  AND previous_arrival_delay IS NULL
GROUP BY airline
ORDER BY next_flight_delay_rate DESC;

SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'aircraft_sequence_2025'
ORDER BY ordinal_position;

SELECT
    reporting_airline,
    COUNT(*) AS connections,
    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE departure_delayed_15 = 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS next_flight_delay_rate
FROM public.aircraft_sequence_2025
WHERE is_valid_connection = TRUE
  AND previous_arrival_delay IS NULL
GROUP BY reporting_airline
ORDER BY next_flight_delay_rate DESC;

SELECT
    CASE
        WHEN turnaround_minutes <= 30 THEN '0-30 min'
        WHEN turnaround_minutes <= 60 THEN '31-60 min'
        WHEN turnaround_minutes <= 90 THEN '61-90 min'
        WHEN turnaround_minutes <= 120 THEN '91-120 min'
        WHEN turnaround_minutes <= 180 THEN '121-180 min'
        ELSE '180+ min'
    END AS turnaround_bucket,
    COUNT(*) AS connections,
    COUNT(*) FILTER (
        WHERE departure_delayed_15 = 1
    ) AS delayed_next_flights,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE departure_delayed_15 = 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS next_flight_delay_rate
FROM public.aircraft_sequence_2025
WHERE is_valid_connection = TRUE
  AND previous_arrival_delay IS NULL
  AND turnaround_minutes IS NOT NULL
GROUP BY 1
ORDER BY MIN(turnaround_minutes);

SELECT
    COUNT(*) AS total_missing_previous_delay,
    COUNT(*) FILTER (
        WHERE previous_arrival IS NULL
    ) AS missing_previous_arrival,
    COUNT(*) FILTER (
        WHERE previous_destination IS NULL
    ) AS missing_previous_destination,
    COUNT(*) FILTER (
        WHERE previous_arrival IS NOT NULL
    ) AS previous_arrival_present,
    COUNT(*) FILTER (
        WHERE previous_destination IS NOT NULL
    ) AS previous_destination_present
FROM public.aircraft_sequence_2025
WHERE is_valid_connection = TRUE
  AND previous_arrival_delay IS NULL;


  SELECT
    tail_number,
    flight_date,
    reporting_airline,
    flight_number,
    previous_arrival,
    previous_destination,
    previous_arrival_delay,
    previous_arrival_delayed_15,
    turnaround_minutes,
    departure_delay,
    departure_delayed_15,
    arrival_delay
FROM public.aircraft_sequence_2025
WHERE is_valid_connection = TRUE
  AND previous_arrival_delay IS NULL
ORDER BY turnaround_minutes
LIMIT 20;


SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'flights_2025'
ORDER BY ordinal_position;

SELECT
    a.tail_number,
    a.flight_date,
    a.reporting_airline,
    a.flight_number,
    a.previous_arrival,
    a.previous_destination,
    COUNT(f."Tail_Number") AS matching_source_flights,
    COUNT(f."ArrDelay") AS source_arrival_delay_present,
    MIN(f."ArrDelay") AS source_arrival_delay_minutes
FROM public.aircraft_sequence_2025 a
LEFT JOIN public.flights_2025 f
    ON f."Tail_Number" = a.tail_number
   AND f."FlightDate"::date = a.previous_arrival::date
   AND f."Dest" = a.previous_destination
   AND f."ActualArrival" = a.previous_arrival
WHERE a.is_valid_connection = TRUE
  AND a.previous_arrival_delay IS NULL
GROUP BY
    a.tail_number,
    a.flight_date,
    a.reporting_airline,
    a.flight_number,
    a.previous_arrival,
    a.previous_destination
ORDER BY MIN(a.turnaround_minutes)
LIMIT 20;

SELECT
    f."FlightDate",
    f."Reporting_Airline",
    f."Flight_Number_Reporting_Airline",
    f."Tail_Number",
    f."Origin",
    f."Dest",
    f."ArrTime",
    f."ActualArrival",
    f."ArrDelay",
    f."Cancelled",
    f."Diverted"
FROM public.flights_2025 f
WHERE f."Tail_Number" IN ('N398DN', 'N612QX', 'N568NN', 'N461SW')
ORDER BY f."Tail_Number", f."FlightDate", f."ActualArrival"
LIMIT 50;


SELECT
    a.tail_number,
    a.previous_arrival,
    a.previous_destination,
    a.turnaround_minutes,
    f."Flight_Number_Reporting_Airline" AS previous_flight_number,
    f."Cancelled",
    f."Diverted",
    f."ActualArrival",
    f."ArrDelay"
FROM public.aircraft_sequence_2025 a
JOIN public.flights_2025 f
    ON f."Tail_Number" = a.tail_number
   AND f."ActualArrival" = a.previous_arrival
   AND f."Dest" = a.previous_destination
WHERE a.is_valid_connection = TRUE
  AND a.previous_arrival_delay IS NULL
ORDER BY a.turnaround_minutes
LIMIT 30;


SELECT
    f."Diverted",
    f."Cancelled",
    COUNT(*) AS connections,
    COUNT(*) FILTER (
        WHERE a.departure_delayed_15 = 1
    ) AS delayed_next_flights,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE a.departure_delayed_15 = 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS next_flight_delay_rate
FROM public.aircraft_sequence_2025 a
JOIN public.flights_2025 f
    ON f."Tail_Number" = a.tail_number
   AND f."ActualArrival" = a.previous_arrival
   AND f."Dest" = a.previous_destination
WHERE a.is_valid_connection = TRUE
  AND a.previous_arrival_delay IS NULL
GROUP BY f."Diverted", f."Cancelled"
ORDER BY connections DESC;


SELECT
    (SELECT COUNT(DISTINCT airport)
     FROM public.vw_airport_delay_summary)
        AS airports_analyzed,

    (SELECT SUM(operated_flights)
     FROM public.vw_airport_delay_summary)
        AS airport_flight_total,

    (SELECT ROUND(
        100.0 * SUM(delayed_departures)
        / NULLIF(SUM(operated_flights), 0), 2)
     FROM public.vw_airport_delay_summary)
        AS airport_departure_delay_rate_pct,

    (SELECT COUNT(DISTINCT route)
     FROM public.vw_route_delay_summary)
        AS routes_analyzed,

    (SELECT SUM(operated_flights)
     FROM public.vw_route_delay_summary)
        AS route_flight_total,

    (SELECT ROUND(
        SUM(avg_departure_delay * operated_flights)
        / NULLIF(SUM(operated_flights), 0), 2)
     FROM public.vw_airport_delay_summary)
        AS weighted_average_departure_delay;


		SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'vw_airport_delay_summary'
  AND column_name IN (
      'avg_departure_delay',
      'operated_flights',
      'delayed_departures'
  )
ORDER BY column_name;

SELECT pg_get_viewdef(
    'public.vw_airport_delay_summary'::regclass,
    true


	SELECT
    ROUND(AVG("DepDelay")::numeric, 2)
        AS overall_average_departure_delay,
    COUNT("DepDelay")
        AS flights_with_departure_delay_data,
    COUNT(*)
        AS non_cancelled_flights
FROM public.flights_2025
WHERE "Cancelled" = 0;
);