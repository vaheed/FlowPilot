# NetFlow-Kafka-ClickHouse Stack

This project provides a containerized environment to collect NetFlow data using `nfacctd`, stream it into Apache Kafka, and store/analyze it with ClickHouse. It uses Docker Compose to orchestrate the services.

## Contents

- `docker-compose.yml` — Multi-service orchestration file.
- `configs/` — Configuration files:
  - `clickhouse-init.sql`: ClickHouse initialization SQL script.
  - `nfacctd.conf`: nfacctd configuration.

## Services

### 1. Apache Kafka

- **Image:** `apache/kafka:3.7.2`
- **Ports:** Exposed internally; not mapped to host.
- **Volumes:**
  - `./kafka-data:/var/lib/kafka/data`
  - `./kafka-cluster-data:/var/lib/kafka/cluster-data`
- **Cluster:** Single-node (for demo/dev).

### 2. ClickHouse

- **Image:** `clickhouse:lts`
- **Volumes:**
  - `./clickhouse-data:/var/lib/clickhouse`
  - `./configs/clickhouse-init.sql:/docker-entrypoint-initdb.d/init.sql`
- **Environment:**
  - User: `admin`
  - Password: `secure_password`

### 3. nfacctd

- **Image:** `pmacct/nfacctd:latest`
- **Ports:** `2055/udp` (NetFlow)
- **Volumes:**
  - `./configs/nfacctd.conf:/etc/pmacct/nfacctd.conf`
- **Depends on:** Kafka

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone https://github.com/vaheed/flowpilot/
   cd flowpilot
   ```

2. **Prepare configuration files:**
   - Edit `configs/nfacctd.conf` and `configs/clickhouse-init.sql` if needed.

3. **Start the stack:**
   ```bash
   mkdir clickhouse-data kafka-cluster-data kafka-data
   chmod 777 clickhouse-data kafka-cluster-data kafka-data
   docker compose up -d
   ```

4. **Check service health:**
   - Kafka: Should be running as `kafka` container.
   - ClickHouse: Should be running as `clickhouse` container.
   - nfacctd: Should be running as `nfacctd` container.

5. **Send NetFlow traffic:**  
   Send NetFlow v5/v9/IPFIX to `UDP/2055` on your Docker host.

6. **Access ClickHouse:**  
   - Connect via `clickhouse-client` inside the container or expose ports as needed.
   - Use credentials:
     - User: `admin`
     - Password: `secure_password`

## Data Flow

```
[ NetFlow Exporter ] --(UDP/2055)--> [ nfacctd ] --(Kafka)--> (consumer)--> [ ClickHouse ]
```

---

## 1. Check if Data Is Being Ingested

Count total rows in both the raw Kafka table and the final processed storage table:

```sql
-- Count total rows in raw Kafka table
SELECT count() FROM netflow_db.kafka_netflow_raw;

-- Count total rows in final storage table
SELECT count() FROM netflow_db.netflow;
```

If `kafka_netflow_raw` has data but `netflow` does not, check:
- That your Materialized View (`netflow_mv`) is working.
- Kafka connectivity and topic name.

---

## 2. Sample Raw Data from Kafka Table

See a few raw rows from the Kafka input:

```sql
SELECT * FROM netflow_db.kafka_netflow_raw LIMIT 5;
```

---

## 3. Sample Processed Data in Storage Table

Show a few processed rows:

```sql
SELECT * FROM netflow_db.netflow LIMIT 5;
```

Check if fields like `stamp_inserted`, `ip_src`, `bytes`, etc., look correct.

---

## 4. Check Latest Inserted Timestamps

Validate real-time data flow:

```sql
-- Get latest timestamp inserted
SELECT max(stamp_inserted) FROM netflow_db.netflow;

-- Get first and last timestamps
SELECT 
    min(stamp_inserted) AS first_seen,
    max(stamp_inserted) AS last_seen
FROM netflow_db.netflow;
```

---

## 5. Top IPs by Traffic (Data Volume)

Identify top source IPs by total bytes in the last hour—a common Lawful Intercept (LI) use case:

```sql
SELECT
    ip_src,
    sum(bytes) AS total_bytes
FROM netflow_db.netflow
WHERE stamp_inserted >= now() - INTERVAL 1 HOUR
GROUP BY ip_src
ORDER BY total_bytes DESC
LIMIT 10;
```

---

## 6. Traffic Between Two IPs

Investigate flows between specific source and destination IPs:

```sql
SELECT *
FROM netflow_db.netflow
WHERE ip_src = '192.168.1.10'
  AND ip_dst = '8.8.8.8'
ORDER BY stamp_inserted DESC
LIMIT 10;
```

---

## 7. Hourly Traffic Aggregation (via Materialized View)

See pre-aggregated hourly traffic stats, useful for dashboards and reporting:

```sql
SELECT
    hour_bucket,
    ip_src,
    ip_dst,
    packets_total,
    bytes_total
FROM netflow_db.netflow_aggr_hourly
ORDER BY hour_bucket DESC
LIMIT 10;
```

---

## 8. Monthly Totals (via Monthly Materialized View)

Get long-term analytics and archival comparisons:

```sql
SELECT
    month_bucket,
    ip_src,
    ip_dst,
    packets_total,
    bytes_total
FROM netflow_db.netflow_aggr_monthly
ORDER BY month_bucket DESC
LIMIT 10;
```

---

## 9. Number of Rows Per Day (Partitioning Check)

Verify partitioning and TTL (Time-To-Live) cleanup:

```sql
SELECT
    toDate(stamp_inserted) AS date,
    count() AS row_count
FROM netflow_db.netflow
GROUP BY date
ORDER BY date DESC;
```

---

## 10. Disk Usage Per Table

Check disk usage for each table—important for capacity planning and tuning:

```sql
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) AS size,
    count() AS parts
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY size DESC;
```

---

## 11. View Table Schema

Describe the schema of your main NetFlow table (helpful for debugging and reporting):

```sql
DESCRIBE TABLE netflow_db.netflow;
```

---

## Bonus: Real-Time Bandwidth Monitoring (Last 5 Minutes)

Monitor bandwidth usage in (approximately) real-time:

```sql
SELECT
    floor(toUInt32(now() - stamp_inserted) / 60) AS minute_ago,
    formatReadableSize(sum(bytes)) AS total_data,
    sum(packets) AS total_packets
FROM netflow_db.netflow
WHERE stamp_inserted >= now() - INTERVAL 5 MINUTE
GROUP BY minute_ago
ORDER BY minute_ago ASC;
```
Visualizing this output gives you a real-time bandwidth graph.

---

## Usage Notes

- Replace database/table names as needed for your deployment.
- These queries are intended for environments where ClickHouse is used for NetFlow analytics with Kafka ingestion and Materialized Views.
- For troubleshooting ingestion or aggregation issues, always start with the ingestion validation and sampling queries.

---

**Happy Monitoring!**

## Notes

- Data directories are persisted locally; remove or back up as needed.
- Adjust resource limits in `docker-compose.yml` for production use.
- This stack is for development/demo purposes (single broker, single ClickHouse node).

## License

MIT (adapt as needed)
