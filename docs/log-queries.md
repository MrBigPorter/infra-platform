# 🔍 LogQL Query Reference

> Practical LogQL queries for day-to-day debugging and monitoring in Grafana Explore.

---

## Query Structure

```logql
{<label_selector>} <pipe_operations> | <filter>
```

| Part | Example | Purpose |
|------|---------|---------|
| **Label selector** | `{container="hyperpush-app-1"}` | Which containers? |
| **Pipe operations** | `\| json` | Transform/extract fields |
| **Filter** | `\|= "error"` | Search within log content |

---

## Label Selectors

### By Container Name

```logql
{container="hyperpush-app-1"}
{container="infra-grafana"}
{container=~"hyperpush.*"}       # Regex: all hyperpush containers
```

### By Docker Compose Project

```logql
{compose_project="hyperpush"}
{compose_project=~"hyperpush|joymini"}  # Multiple projects
```

### By Service

```logql
{service="backend"}
{service="nginx"}
```

### By Log Level

```logql
{level="error"}
{level=~"error|warn"}
{level="30"}        # Pino numeric level
```

### Combined

```logql
{compose_project="hyperpush", level="error"}
```

---

## Filtering Log Content

### Contains a string

```logql
{container="hyperpush-app-1"} |= "error"
{container="hyperpush-app-1"} |= "Unsupported route"
```

### Does NOT contain a string

```logql
{container="hyperpush-app-1"} != "health"
```

### Regex match

```logql
{container="hyperpush-app-1"} |~ "error|Error|ERROR"
```

### Regex NOT match

```logql
{container="hyperpush-app-1"} !~ "heartbeat|health"
```

---

## JSON Field Extraction

Pino logs are JSON. Use `| json` to extract fields:

### Extract all JSON fields

```logql
{container="hyperpush-app-1"} | json
```

This makes `level`, `msg`, `context`, `requestId`, `pid`, `hostname` available as fields.

### Filter by extracted field

```logql
{container="hyperpush-app-1"} | json | level = "error"
{container="hyperpush-app-1"} | json | context = "AuthService"
{container="hyperpush-app-1"} | json | level = "warn" and msg =~ ".*timeout.*"
```

### Format output with line_format

```logql
{container="hyperpush-app-1"} | json
| line_format "{{.context}} | {{.msg}}"
```

---

## Rate and Count Queries

### Logs per second (rate)

```logql
rate({compose_project="hyperpush"}[5m])
```

### Count of error logs per minute

```logql
sum by (container) (
  count_over_time({compose_project="hyperpush"} | json | level = "error" [1m])
)
```

### Top 5 noisiest containers

```logql
topk(5, sum by (container) (
  count_over_time({compose_project="hyperpush"}[1h])
))
```

---

## Time Range Queries

### Last 15 minutes only

```
Time range selector in Grafana UI: Last 15 minutes
```

```logql
{container="hyperpush-app-1"} |= "error"
```

### Specific time window (in LogQL)

```logql
{container="hyperpush-app-1"} |= "error"
```

> Set time range in Grafana's time picker — no special syntax needed.

---

## Practical Templates

### 1. Quick error check

```logql
{compose_project="hyperpush"} | json | level = "error"
```

### 2. Deployment verification (check if app started)

```logql
{container="hyperpush-app-1"} |= "Nest application successfully started"
```

### 3. GraphQL request tracing

```logql
{container="hyperpush-app-1"} | json | requestId != ""
```

### 4. Database connection issues

```logql
{container="hyperpush-app-1"} |= "database" or container="hyperpush-app-1" |= "postgres" or container="hyperpush-app-1" |= "prisma"
```

### 5. Authentication failures

```logql
{compose_project="hyperpush"} | json | context = "AuthService" and level = "warn"
```

### 6. All logs from a specific deployment

```logql
{compose_project="hyperpush"} | json
| line_format "{{.time}} [{{.level}}] {{.context}}: {{.msg}}"
```

### 7. Rate of errors over time (graph)

```logql
sum by (container) (
  rate(
    {compose_project="hyperpush"} | json | level = "error" [5m]
  )
)
```

> Switch to "Graph" visualization in Grafana for time-series charts.

---

## Dashboard Panels

For creating Grafana dashboard panels, these queries work well:

| Panel Type | Query | Description |
|------------|-------|-------------|
| **Logs** | `{compose_project="hyperpush"} \| json` | All logs as a stream |
| **Time series** | `rate({compose_project="hyperpush"}[5m])` | Log volume over time |
| **Stat** | `count_over_time({compose_project="hyperpush"} \| json \| level = "error" [24h])` | Total errors in 24h |
| **Table** | `topk(10, sum by (container) (count_over_time({compose_project="hyperpush"}[1h])))` | Top containers by log count |

---

## HyperPush-Specific Queries

> These queries are tailored for the [HyperPush](https://github.com/MrBigPorter/hyperpush) project — now live in production.

### 8. Auth failures by user activity

```logql
{compose_project="hyperpush"} | json | context = "AuthService" and level = "warn"
```

### 9. GraphQL resolver tracing (exclude health checks)

```logql
{compose_project="hyperpush"} | json | context = "GraphQLResolver" and msg != "health check"
```

### 10. Deployment verification (app started)

```logql
{container="hyperpush-app"} |= "Nest application successfully started"
```

### 11. Application audit logs (GraphQL audit trail)

```logql
{container="hyperpush-app"} | json | context = "AuditLogService"
```

### 12. Database errors (Prisma / PostgreSQL)

```logql
{compose_project="hyperpush"} | json | level = "error" and (msg =~ ".*prisma.*" or msg =~ ".*database.*" or msg =~ ".*postgres.*")
```

### 13. CodePush server operations

```logql
{container="hyperpush-codepush-prod"} | json
```

### 14. All HyperPush containers in one view

```logql
{compose_project="hyperpush"} | json
| line_format "{{.time}} [{{.level}}] {{.container}}/{{.context}}: {{.msg}}"
```

### 15. Rate of errors across all HyperPush containers (graph)

```logql
sum by (container) (
  rate(
    {compose_project="hyperpush"} | json | level = "error" [5m]
  )
)
```

---

## Reference: Pino Log Levels

| Numeric Level | Label | Description |
|--------------|-------|-------------|
| `10` | trace | Debugging, verbose |
| `20` | debug | Development debugging |
| `30` | **info** | Normal operation (most logs) |
| `40` | **warn** | Warnings, deprecations |
| `50` | **error** | Errors, exceptions |
| `60` | fatal | Critical, unrecoverable |
