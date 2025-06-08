-- 0. Create the database
DROP DATABASE IF EXISTS netflow_db;
CREATE DATABASE netflow_db;
USE netflow_db;

-- 1. Kafka raw ingestion table
CREATE TABLE kafka_netflow_raw (
    event_type String,
    ip_src String,
    ip_dst String,
    port_src UInt16,
    post_nat_ip_src String,
    post_nat_port_dst UInt16,
    timestamp_start DateTime64(6, 'UTC'),
    stamp_inserted DateTime64(0, 'UTC'),
    stamp_updated DateTime64(0, 'UTC'),
    packets UInt64,
    bytes UInt64,
    writer_id String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'netflow',
    kafka_group_name = 'clickhouse',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 3;

-- 2. Main Netflow Table (IPv4 stored as UInt32)
CREATE TABLE netflow (
    ip_src UInt32 CODEC(ZSTD(3)),
    ip_dst UInt32 CODEC(ZSTD(3)),
    port_src UInt16,
    post_nat_ip_src UInt32 CODEC(ZSTD(3)),
    post_nat_port_dst UInt16,
    stamp_inserted DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(3)),
    stamp_updated DateTime64(0, 'UTC'),
    packets UInt64 CODEC(T64, ZSTD(3)),
    bytes UInt64 CODEC(T64, ZSTD(3))
)
ENGINE = MergeTree
PARTITION BY toStartOfHour(stamp_inserted)
ORDER BY (stamp_inserted, ip_src, ip_dst, port_src)
TTL toDateTime(stamp_inserted) + INTERVAL 90 DAY
SETTINGS index_granularity = 4096, merge_with_ttl_timeout = 3600;

-- 2a. Skip indexes for faster filtering
ALTER TABLE netflow
    ADD INDEX idx_tuple_ips (tuple(ip_src, ip_dst)) TYPE minmax GRANULARITY 1,
    ADD INDEX idx_ip_src (ip_src) TYPE set(100) GRANULARITY 1,
    ADD INDEX idx_ip_dst (ip_dst) TYPE set(100) GRANULARITY 1,
    ADD INDEX idx_port_src (port_src) TYPE set(100) GRANULARITY 1,
    ADD INDEX idx_port_dst (post_nat_port_dst) TYPE set(100) GRANULARITY 1;

-- 3. Materialized View: Convert IPv4 strings to UInt32 (with correct WHERE logic)
CREATE MATERIALIZED VIEW netflow_mv
TO netflow
AS
SELECT
    IPv4StringToNum(ip_src) AS ip_src,
    IPv4StringToNum(ip_dst) AS ip_dst,
    port_src,
    IPv4StringToNum(post_nat_ip_src) AS post_nat_ip_src,
    post_nat_port_dst,
    toDateTime64(toStartOfMillisecond(timestamp_start), 3, 'UTC') AS stamp_inserted,
    stamp_updated,
    packets,
    bytes
FROM (
    SELECT *
    FROM kafka_netflow_raw
    WHERE isIPv4String(ip_src) AND isIPv4String(ip_dst) AND isIPv4String(post_nat_ip_src)
);

-- 4. Query Helpers (convert back to human-readable IPs)
-- Example query:
-- SELECT
--     IPv4NumToString(ip_src) AS ip_src,
--     IPv4NumToString(ip_dst) AS ip_dst,
--     port_src,
--     packets,
--     bytes,
--     stamp_inserted
-- FROM netflow
-- WHERE ip_src = IPv4StringToNum('192.168.1.1')
-- ORDER BY stamp_inserted DESC
-- LIMIT 10;
