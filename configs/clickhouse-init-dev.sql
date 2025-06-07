-- 0. Create the database
DROP DATABASE IF EXISTS netflow_db;
CREATE DATABASE netflow_db;
USE netflow_db;

-- 1. Temporary Kafka raw table
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

-- 2. Main Netflow Table (optimized for fast queries)
CREATE TABLE netflow (
    ip_src FixedString(16) CODEC(ZSTD(3)),         -- For IPv4/IPv6 (store as binary, 16 bytes covers both)
    ip_dst FixedString(16) CODEC(ZSTD(3)),
    port_src UInt16,
    post_nat_ip_src FixedString(16) CODEC(ZSTD(3)),
    post_nat_port_dst UInt16,
    stamp_inserted DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(3)), -- ms precision
    stamp_updated DateTime64(0, 'UTC'),
    packets UInt64 CODEC(T64, ZSTD(3)),
    bytes UInt64 CODEC(T64, ZSTD(3))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDDhh(stamp_inserted)    -- **Partition by HOUR** for fine pruning
ORDER BY (stamp_inserted, ip_src, ip_dst, port_src) -- **ORDER for time/IP/port-based queries**
TTL stamp_inserted + INTERVAL 2 DAY
SETTINGS
    index_granularity = 4096,        -- **Finer granularity for faster seeks**
    merge_with_ttl_timeout = 3600;   -- Merge expired data every hour

-- 2a. Advanced Skip Indexes for Query Speed
ALTER TABLE netflow
    ADD INDEX idx_tuple_ips (tuple(ip_src, ip_dst)) TYPE minmax GRANULARITY 1,
    ADD INDEX idx_ip_src (ip_src) TYPE set(100) GRANULARITY 1,
    ADD INDEX idx_ip_dst (ip_dst) TYPE set(100) GRANULARITY 1,
    ADD INDEX idx_port_src (port_src) TYPE set(100) GRANULARITY 1,
    ADD INDEX idx_port_dst (post_nat_port_dst) TYPE set(100) GRANULARITY 1;

-- 3. Materialized View: transform, convert IPs to binary for storage
CREATE MATERIALIZED VIEW netflow_mv
TO netflow
AS
SELECT
    reinterpretAsFixedString(ip_src, 16) AS ip_src,
    reinterpretAsFixedString(ip_dst, 16) AS ip_dst,
    port_src,
    reinterpretAsFixedString(post_nat_ip_src, 16) AS post_nat_ip_src,
    post_nat_port_dst,
    toDateTime64(toStartOfMillisecond(timestamp_start), 3, 'UTC') AS stamp_inserted,
    stamp_updated,
    packets,
    bytes
FROM kafka_netflow_raw;

-- 4. Helper Table Functions for Querying (for test/dev)
-- Use these in your SELECTs to convert FixedString(16) back to readable IPs:
-- SELECT IPv6NumToString(reinterpretAsUInt128(ip_src)) AS ip_src, ... FROM netflow WHERE ...
-- ---------------------------------------------
-- Example Queries (uncomment and run manually)
-- ---------------------------------------------

/*
-- IPv4 Example #1: Find all flows FROM IPv4 address 192.0.2.1
SELECT
    IPv6NumToString(reinterpretAsUInt128(ip_src)) AS ip_src,
    IPv6NumToString(reinterpretAsUInt128(ip_dst)) AS ip_dst,
    port_src,
    packets,
    bytes,
    stamp_inserted
FROM netflow
WHERE reinterpretAsUInt128(ip_src) = IPv4StringToNum('192.0.2.1')
ORDER BY stamp_inserted DESC
LIMIT 10;
*/

/*
-- IPv4 Example #2: Find all flows TO IPv4 address 198.51.100.5
SELECT
    IPv6NumToString(reinterpretAsUInt128(ip_src)) AS ip_src,
    IPv6NumToString(reinterpretAsUInt128(ip_dst)) AS ip_dst,
    port_src,
    packets,
    bytes,
    stamp_inserted
FROM netflow
WHERE reinterpretAsUInt128(ip_dst) = IPv4StringToNum('198.51.100.5')
ORDER BY stamp_inserted DESC
LIMIT 10;
*/

/*
-- IPv6 Example: Find all flows to destination IPv6 ::1
SELECT
    IPv6NumToString(reinterpretAsUInt128(ip_dst)) AS ip_dst,
    port_src,
    packets,
    bytes,
    stamp_inserted
FROM netflow
WHERE reinterpretAsUInt128(ip_dst) = IPv6StringToNum('::1')
ORDER BY stamp_inserted DESC
LIMIT 10;
*/

/*
-- Top IPv4 Talkers (by bytes) in the last hour
SELECT
    IPv6NumToString(reinterpretAsUInt128(ip_src)) AS ip_src,
    sum(bytes) AS total_bytes
FROM netflow
WHERE stamp_inserted >= now() - INTERVAL 1 HOUR
  AND isIPv4(reinterpretAsUInt128(ip_src))  -- Only IPv4 addresses
GROUP BY ip_src
ORDER BY total_bytes DESC
LIMIT 10;
*/
