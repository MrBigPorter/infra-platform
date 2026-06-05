# 🔧 Operations Guide

> Day-to-day management of the monitoring stack — starting, stopping, monitoring disk usage, and troubleshooting common issues.

---

## Service Management

### Start the stack

```bash
cd /home/user/infra-platform
docker compose -f compose.monitoring.yml up -d
```

### Stop the stack

```bash
docker compose -f compose.monitoring.yml down
```

### Stop and remove volumes (⚠️ destroys all log data)

```bash
docker compose -f compose.monitoring.yml down -v
```

### Restart a single service

```bash
docker compose -f compose.monitoring.yml restart grafana
docker compose -f compose.monitoring.yml restart loki
docker compose -f compose.monitoring.yml restart promtail
```

### View logs of the monitoring stack itself

```bash
docker compose -f compose.monitoring.yml logs --tail=50
docker compose -f compose.monitoring.yml logs --tail=50 promtail
docker compose -f compose.monitoring.yml logs --tail=50 loki
docker compose -f compose.monitoring.yml logs --tail=50 grafana
```

---

## Updating Images

```bash
cd /home/user/infra-platform
docker compose -f compose.monitoring.yml pull
docker compose -f compose.monitoring.yml up -d
```

---

## Disk Management

### Check log storage usage

```bash
# Volume location
docker volume inspect infra-platform_loki-data
# Returns Mountpoint: /var/lib/docker/volumes/infra-platform_loki-data/_data

# Check actual disk usage
sudo du -sh /var/lib/docker/volumes/infra-platform_loki-data/_data
```

### Expected disk usage

| Scenario | Est. Size | Notes |
|----------|-----------|-------|
| 1 day, 3 containers | ~1-2 GB | Light usage |
| 10 days, 5 containers | ~10-20 GB | Full retention period |
| 30 days, 10 containers | ~50-100 GB | Need to extend retention |

### Reduce disk usage (manual cleanup)

```bash
# Option 1: Delete old data (⚠️ irreversible)
docker compose -f compose.monitoring.yml down
docker volume rm infra-platform_loki-data
docker compose -f compose.monitoring.yml up -d
```

### Change retention period

Edit [`loki-config.yml`](../loki-config.yml):

```yaml
limits_config:
  retention_period: 168h   # Change from 240h to 168h (7 days)
```

Then restart Loki:

```bash
docker compose -f compose.monitoring.yml restart loki
```

> **Note**: Changing retention doesn't delete existing data immediately. Loki's compactor process cleans up old data on its own schedule. For immediate cleanup, delete the volume and restart.

---

## Grafana Administration

### Reset admin password

If you forget the admin password:

```bash
# Stop Grafana
docker compose -f compose.monitoring.yml stop grafana

# Find the Grafana database
docker volume inspect infra-platform_grafana-data
# Mountpoint: /var/lib/docker/volumes/infra-platform_grafana-data/_data

# Start a temporary container to reset password
docker run --rm -it \
  -v infra-platform_grafana-data:/var/lib/grafana \
  --entrypoint /bin/sh \
  grafana/grafana:latest \
  -c "grafana-cli admin reset-admin-password --homepath /usr/share/grafana admin123"

# Restart Grafana
docker compose -f compose.monitoring.yml start grafana
```

New password: `admin123`

### Change admin password via UI

1. Login to Grafana
2. Go to **Administration** → **Users and access** → **Users**
3. Click on **admin**
4. Click **Change password**

### Set password via environment variable (recommended)

Create a `.env` file alongside `compose.monitoring.yml`:

```bash
GRAFANA_ADMIN_PASSWORD=your-strong-password
```

Then restart:

```bash
docker compose -f compose.monitoring.yml down
docker compose -f compose.monitoring.yml up -d
```

---

## LogQL Utility Queries

### Check if Promtail is receiving logs

```logql
{container="infra-promtail"}
```

### Check Loki's internal logs

```logql
{container="infra-loki"}
```

### Count unique containers sending logs

```logql
count by (container) (
  count_over_time({__name__=~".+"}[5m])
)
```

---

## Troubleshooting

### Problem: Grafana shows "No data" or "Loki: Bad Gateway (504)"

**Possible causes:**
1. Loki container is not running
2. Loki is overloaded or OOM

**Check:**
```bash
docker compose -f compose.monitoring.yml ps
docker compose -f compose.monitoring.yml logs --tail=20 loki
```

**Solution:** Restart Loki
```bash
docker compose -f compose.monitoring.yml restart loki
```

### Problem: Promtail not collecting logs

**Check Promtail's own logs:**
```bash
docker compose -f compose.monitoring.yml logs --tail=30 promtail
```

**Verify docker.sock access:**
```bash
docker compose -f compose.monitoring.yml exec promtail ls -la /var/run/docker.sock
# Expected: srw-rw---- 1 root docker 0 ... /var/run/docker.sock
```

**Verify containers are discoverable:**
```bash
docker compose -f compose.monitoring.yml exec promtail \
  wget -qO- http://loki:3100/loki/api/v1/labels
# Should return JSON with container, compose_project, level, etc.
```

### Problem: `monitor.joyminins.com` returns 502/504

**Check Nginx:**
```bash
# Verify 50-monitor.conf is loaded
docker compose -f /path/to/JoyMini/compose.prod.yml exec nginx nginx -T | grep monitor

# Check Nginx error logs
docker compose -f /path/to/JoyMini/compose.prod.yml logs nginx --tail=20
```

**Check Grafana:**
```bash
curl -I http://localhost:3001
# Expected: HTTP/1.1 200 OK
```

**Check `host.docker.internal` resolution:**
```bash
docker compose -f /path/to/JoyMini/compose.prod.yml exec nginx \
  ping host.docker.internal
```

### Problem: Loki using too much disk

**Quick check:**
```bash
sudo du -sh /var/lib/docker/volumes/infra-platform_loki-data/_data
```

**Short-term fix:** Reduce retention period in `loki-config.yml`, restart Loki.

**Long-term fix:** Add a disk monitoring alert in Grafana.

### Problem: Promtail fails with "permission denied" on docker.sock

**Symptom in promtail logs:**
```
level=error msg="error reading docker logs" err="permission denied"
```

**Solution:** Ensure the docker.sock mount has correct permissions:
```yaml
# compose.monitoring.yml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro   # Note: :ro is read-only
```

The container runs as root (default), which should have access. If using a non-root user, add the user to the `docker` group or use a privileged container.

### Problem: HyperPush logs not appearing in Grafana

**Check if hyperpush containers are running:**
```bash
docker ps | grep hyperpush
```

**Verify Promtail can see them:**
```bash
docker compose -f compose.monitoring.yml exec promtail \
  wget -qO- http://loki:3100/loki/api/v1/labels
# Should include "hyperpush" in compose_project labels
```

**Check HyperPush is outputting logs (Pino JSON):**
```bash
docker logs --tail=10 hyperpush-app
# Expected: JSON lines like {"level":30,"msg":"...","context":"..."}
```

**Try a specific LogQL query:**
```
{compose_project="hyperpush"} | json | level = "error"
```

### Problem: Grafana dashboard not showing HyperPush data

**Check that the dashboard was provisioned:**
```bash
docker compose -f compose.monitoring.yml exec grafana \
  ls -la /etc/grafana/provisioning/dashboards/json/
# Should show hyperpush-dashboard.json
```

**Check Grafana provisioning logs:**
```bash
docker compose -f compose.monitoring.yml logs --tail=20 grafana | grep -i provision
```

**Manually reload dashboards:**
1. Grafana → Administration → Plugins and data → Data sources
2. Verify Loki datasource exists
3. Go to Dashboards → Browse → check if HyperPush folder exists

---

## Health Check Endpoints

| Service | Endpoint | Purpose |
|---------|----------|---------|
| **Loki** | `http://localhost:3100/ready` | Returns `Ready` if Loki is operational |
| **Loki** | `http://localhost:3100/metrics` | Prometheus metrics |
| **Grafana** | `http://localhost:3001/api/health` | Returns `{"database": "ok"}` |

```bash
# Quick health check
curl -s http://localhost:3100/ready
# Should output: Ready

curl -s http://localhost:3001/api/health
# Should output: {"database":"ok"}
```

---

## Backup

### Backup Grafana configuration

```bash
# Export dashboards
docker compose -f compose.monitoring.yml exec grafana \
  wget -qO- http://admin:${GRAFANA_ADMIN_PASSWORD:-admin}@localhost:3000/api/search

# Grafana's database (SQLite)
sudo cp /var/lib/docker/volumes/infra-platform_grafana-data/_data/grafana.db \
  ~/backups/grafana-$(date +%Y%m%d).db
```

### Loki logs are not typically backed up

Loki's purpose is operational debugging — logs are ephemeral. If you need long-term retention, consider extending the retention period or adding an S3 storage backend.
