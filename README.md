# NetFlow-Kafka-ClickHouse Stack

This project provides a containerized environment to collect NetFlow data using `nfacctd`, stream it into Apache Kafka, and store/analyze it with ClickHouse. It uses Docker Compose to orchestrate the services.

## Contents

- `docker-compose.yml` — Multi-service orchestration file.
- `configs/` — Configuration files:
  - `clickhouse-init.sql`: ClickHouse initialization SQL script.
  - `nfacctd.conf`: nfacctd configuration.
- `kafka-data/`, `kafka-cluster-data/`, `clickhouse-data/` — Data volumes for Kafka and ClickHouse persistence.

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
   git clone <your-repo-url>
   cd <your-repo-directory>
   ```

2. **Prepare configuration files:**
   - Edit `configs/nfacctd.conf` and `configs/clickhouse-init.sql` if needed.

3. **Start the stack:**
   ```bash
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
[ NetFlow Exporter ] --(UDP/2055)--> [ nfacctd ] --(Kafka)--> [ Kafka ] --(consumer)--> [ ClickHouse ]
```

## Notes

- Data directories are persisted locally; remove or back up as needed.
- Adjust resource limits in `docker-compose.yml` for production use.
- This stack is for development/demo purposes (single broker, single ClickHouse node).

## License

MIT (adapt as needed)
