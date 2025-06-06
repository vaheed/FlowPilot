-- 0. Create the database
CREATE DATABASE IF NOT EXISTS netflow_db;

-- 1. Use the database
USE netflow_db;

-- 2. Kafka raw table to consume messages
CREATE TABLE IF NOT EXISTS kafka_netflow_raw (
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

-- 3. Core storage table optimized for queries
CREATE TABLE IF NOT EXISTS netflow (
    ip_src String CODEC(ZSTD(3)),
    ip_dst String CODEC(ZSTD(3)),
    port_src UInt16,
    post_nat_ip_src String CODEC(ZSTD(3)),
    post_nat_port_dst UInt16,
    stamp_inserted DateTime('UTC') CODEC(DoubleDelta, ZSTD(3)),
    stamp_updated DateTime64(0, 'UTC'),
    packets UInt64 CODEC(T64, ZSTD(3)),
    bytes UInt64 CODEC(T64, ZSTD(3))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(stamp_inserted)
ORDER BY (stamp_inserted, ip_src, ip_dst, port_src)
TTL stamp_inserted + INTERVAL 365 DAY
SETTINGS 
    index_granularity = 8192,
    merge_with_ttl_timeout = 86400;

-- 4. Materialized view to transform and load data from Kafka to storage
CREATE MATERIALIZED VIEW IF NOT EXISTS netflow_mv
TO netflow
AS SELECT
    ip_src,
    ip_dst,
    port_src,
    post_nat_ip_src,
    post_nat_port_dst,
    toStartOfSecond(timestamp_start) AS stamp_inserted,
    stamp_updated,
    packets,
    bytes
FROM kafka_netflow_raw;
