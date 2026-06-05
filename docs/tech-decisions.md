# 🔧 Technology Decisions

> Why each component was chosen, what alternatives were considered, and the trade-offs involved.

---

## 1. Why Loki (not Elasticsearch)?

### The Problem

Centralized logging traditionally means **Elasticsearch** — but ES is expensive and operationally complex for a multi-project VPS setup.

### Comparison

| Criteria | Elasticsearch | **Loki** (Chosen) |
|----------|--------------|-------------------|
| **Storage model** | Full-text index on every field | **Label index only**, content compressed |
| **Disk usage for 10GB/day** | ~15-20GB (index + content) | **~2-5GB** (compressed chunks + small index) |
| **Memory** | ~4-8GB minimum | **~512MB-1GB** |
| **Operational complexity** | High (cluster, shards, mappings) | **Low** (single binary, no schema) |
| **Query speed (full text)** | Fast (inverted index) | Slow (sequential chunk scan) |
| **Query speed (label filter)** | Moderate | **Fast** (index lookup) |
| **Docker integration** | Filebeat/Logstash needed | **Native Promtail + docker.sock** |

### Decision

**Loki** — because:
- We filter primarily by **labels** (container name, service, level), not full-text search
- We're running on a single VPS with limited resources (no room for an ES cluster)
- Logs are for **debugging and monitoring**, not analytics — fast label filtering is sufficient
- Promtail's Docker integration is zero-config and elegant

> *"Loki trades search flexibility for operational simplicity and storage efficiency. For container logs on a VPS, that's exactly the right trade."*

---

## 2. Why Promtail (not Filebeat / Fluentd)?

### Alternatives Considered

| Tool | Pros | Cons |
|------|------|------|
| **Filebeat** | Mature, widely used | Requires per-file config, no native Docker discovery |
| **Fluentd** | Powerful plugins, filtering | Heavy (Ruby runtime), complex config, high memory |
| **Vector** | Fast (Rust), modern | Smaller ecosystem, less documentation |
| **Promtail** (Chosen) | Native Grafana integration, Docker SD, JSON pipeline | Only works with Loki |

### Decision

**Promtail** — because:
- **Native Docker service discovery** — `docker_sd_configs` is a single config block that auto-discovers all containers
- **Native Loki push** — direct HTTP POST to Loki, no intermediate buffer or proxy
- **Lightweight** — Go binary, ~30MB memory per instance
- **Pipeline stages** — the `json` stage parses Pino logs without external tools like `jq`

```yaml
# This 15-line config is ALL you need to collect logs from every container on the host
docker_sd_configs:
  - host: unix:///var/run/docker.sock
relabel_configs:
  - source_labels: [__meta_docker_container_name]
    target_label: container
pipeline_stages:
  - json:
      expressions:
        level: level
        msg: msg
```

---

## 3. Why Filesystem Storage (not S3 / GCS)?

### Context

Loki supports multiple storage backends:
- **Local filesystem** (our choice)
- Amazon S3 / S3-compatible (MinIO, etc.)
- Google Cloud Storage
- Azure Blob Storage

### Decision

**Filesystem** — because:
- **Simplicity** — no external dependencies, no credentials, no network latency
- **Single VPS** — there's no second machine to share storage with
- **Performance** — local disk reads are faster than any network call
- **Adequate capacity** — at current scale (10s of GB), a 100GB loki-data volume is trivial

### When to Revisit

If we reach:
- **Multiple VPSes** → S3/MinIO for centralized storage
- **500GB+ logs** → S3 for scalable object storage
- **High availability requirement** → MinIO + Loki microservices mode

---

## 4. Why 10-Day Retention?

### The Trade-off

| Retention | Disk (est.) | Use Case |
|-----------|-------------|----------|
| 24 hours | ~1-2GB | Debugging yesterday's issue |
| **7-10 days** (our choice) | **~10-20GB** | **Debugging last week, incident review** |
| 30 days | ~40-80GB | Monthly compliance, trend analysis |
| 90+ days | ~120-240GB | Audit requirements, historical analysis |

### Decision

**10 days (240h)** — because:
- **Incident review** — most bugs are caught within a few days
- **Release cycle** — enough to cover a full sprint's releases
- **Disk cost** — ~10-20GB is negligible on a modern VPS (100-200GB disk)
- **Configurable** — change one line in `loki-config.yml` to extend if needed

---

## 5. Why Cross-Compose via `host.docker.internal`?

### The Problem

JoyMini Nginx and the monitoring stack are **separate Docker Compose projects**. Docker DNS only resolves container names within the same compose file. How does Nginx reach Grafana?

### Solution: `host.docker.internal:3001`

```yaml
# JoyMini compose.prod.yml
services:
  nginx:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

```nginx
# 50-monitor.conf
location / {
    proxy_pass http://host.docker.internal:3001;
}
```

`host.docker.internal:host-gateway` resolves to the Docker host's internal IP (`172.17.0.1` by default). The monitoring stack binds port `3001` on the host, so Nginx can reach it.

### Alternative: Shared Docker Network

A shared network (`docker network create infra-platform`) could avoid `host.docker.internal`, but would create tighter coupling between the projects. The `host.docker.internal` approach keeps them independent.

---

## 6. Why Self-Signed TLS (not Let's Encrypt)?

### The Architecture

```
Cloudflare (orange cloud) ──TLS──→ VPS:443 ──TLS──→ Nginx ──HTTP──→ Grafana:3001
     ↑ Public TLS                    ↑ Self-signed           ↑ Internal
```

### Why This Works

- **Cloudflare provides the public TLS certificate** — users see a valid HTTPS connection
- **Between Cloudflare and VPS**, traffic is encrypted via Nginx's **self-signed certificate** — no third party can read it
- **Nginx to Grafana** is plain HTTP (inside the VPS, no external access)

### Why Not Let's Encrypt?

Let's Encrypt requires port 80/443 to be directly accessible for ACME challenges — but Cloudflare (orange cloud) proxies all traffic, so the VPS doesn't receive direct HTTP requests on its real IP. The self-signed approach is simpler and equally secure for this architecture.

---

## Summary of Decisions

| Decision | Choice | Key Reason |
|----------|--------|------------|
| Log engine | **Loki** | Cost-effective, Docker-native, sufficient for debugging |
| Log collector | **Promtail** | Zero-config Docker discovery, native Loki integration |
| Storage | **Filesystem** | Simplest for single-VPS, no external dependencies |
| Retention | **10 days** | Balances debugging needs with disk cost |
| Cross-compose | **host.docker.internal** | Keeps projects independent |
| TLS | **Self-signed** | Cloudflare handles public TLS, no ACME needed |
