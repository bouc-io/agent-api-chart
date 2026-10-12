# agent-api-chart

Helm chart for `agent-api-server`, the agentic backend of the bouc.io AI platform: a two-phase
planner/executor loop with tool calling, memory retrieval, and SSE streaming.

## What it deploys

A stateless Deployment plus a ClusterIP Service, backed by two bundled subcharts: **PostgreSQL**
(pinned to the `pgvector/pgvector` image, since the agent shares the platform's vector-capable
Postgres baseline) and **Redis**, which carries the BullMQ job queues and the Redis pub/sub channel
that fans SSE events out to the UIs.

| Object | Name |
|---|---|
| Deployment | `<release>-agent-api-chart` |
| Service | `<release>-agent-api-chart` (port 80 to container port `environment.PORT`) |
| ServiceAccount | `<release>-agent-api-chart` (when `serviceAccount.create`) |
| HorizontalPodAutoscaler | `<release>-agent-api-chart` (when `autoscaling.enabled`) |
| Ingress | `<release>-agent-api-chart` (when `ingress.enabled`) |
| Redis primary Service | `<release>-redis-master` |

The container name inside the pod is `{{ .Chart.Name }}`, i.e. `agent-api-chart`, so use
`-c agent-api-chart` with `kubectl exec`.

Unlike its siblings, this chart has no `env-vars-configmap.yaml`. Every non-secret variable is
rendered inline into the Deployment from `.Values.environment`.

## Values

Values live in three files, matching the convention used across bouc.io charts. There is no plain
`values.yaml`.

| File | Purpose |
|---|---|
| `base.values.yaml` | Values that never change between environments |
| `lcl.values.yaml` | Local cluster overrides |
| `snbx.values.yaml` | Sandbox overrides |

> In the cluster, FluxCD supplies values from generated ConfigMaps via `valuesFrom:`, not from these
> files directly. They are the source the ConfigMaps are generated from.

### Image

`image.registry` and `image.repository` are separate values, joined by the `agent-api-chart.image`
helper. The registry half is what a relocating operator overrides, either per release or through
`global.imageRegistry`. A `repository` whose first path segment already looks like a host is used
verbatim and `registry` is ignored, which keeps older full-string values rendering correctly.

### Credentials

Nothing in this chart holds a password. Both credentials come from Secrets that External Secrets
Operator populates, and both are read with `secretKeyRef`, so no secret material lands in a
ConfigMap:

| Value | Consumed by | Keys used |
|---|---|---|
| `postgresql.auth.existingSecret` | bundled Postgres, and the app | `password` for Postgres, `DATABASE_URL` for the app |
| `redis.auth.existingSecret` | bundled Redis, and the app | `redis-password` for Redis, `REDIS_URL` for the app |

Both are **required** when their subchart is enabled: the helpers fail the render with an explicit
message rather than producing a workload that cannot authenticate. `postgresql.auth.username` and
`postgresql.auth.database` must stay in sync with the DSN that the ExternalSecret template
assembles, since the two build the same connection string from opposite ends.

`redis.enabled` is `false` in `base.values.yaml` and turned on per environment.

### Agent execution knobs

| Value | Default | Meaning |
|---|---|---|
| `environment.MAX_EXECUTION_STEPS` | `10` | Ceiling on executor iterations for one run |
| `environment.EXECUTOR_TIMEOUT_MS` | `300000` | Wall-clock budget for the executor phase |
| `environment.TOOL_DEFAULT_TIMEOUT_MS` | `30000` (set per environment, not in base) | Per-tool timeout when the tool sets none |
| `environment.LLM_BREAKER_THRESHOLD` | `5` | Consecutive LLM failures before the circuit opens |
| `environment.LLM_BREAKER_COOLDOWN_MS` | `30000` | How long the open circuit stays open |
| `environment.SSE_HEARTBEAT_MS` | `15000` | Keepalive interval on the SSE stream |
| `environment.OLLAMA_KEEP_ALIVE` | `10m` | How long the LLM backend holds the model resident |

### Gated capabilities

Two features ship disabled and must be turned on deliberately:

| Value | Default | Meaning |
|---|---|---|
| `environment.EVAL_AUTO_APPROVE` | `"false"` | Master switch letting headless eval runs skip the human approval gate. Set `"true"` only on eval clusters. A per-run flag alone does nothing while this is false |
| `environment.ALLOW_CODE_EXECUTE` | `"false"` | Enables the sandboxed `code_execute` tool. Requires a container runtime reachable from the pod |

The sandbox is tuned by `environment.SANDBOX_IMAGE`, `SANDBOX_TIMEOUT_MS`, `SANDBOX_MEMORY`,
`SANDBOX_CPUS` and `SANDBOX_PIDS`. Those limits constrain the executed code, not the runtime access
the pod is granted.

### Annotations that do real work

- `deploymentAnnotations` carries `reloader.stakater.com/auto: "true"`, applied to the Deployment
  rather than the pod template. A `secretKeyRef` env var is resolved once at pod start and never
  refreshed, so without a restart a rotated database password never takes effect. Inert if Reloader
  is not installed.
- `podAnnotations` carries the Prometheus scrape trio (`prometheus.io/scrape`, `path` `/metrics`,
  `port`). The port value must match the container listen port or the app-level metrics (run counts,
  durations, LLM tokens, tool outcomes) are silently never collected.

## Probes

All three probes are defined, and they use two different endpoints on purpose:

| Probe | Path | Notable setting |
|---|---|---|
| `startupProbe` | `/health/live` | `failureThreshold` 30 at a 5s period, so migrations and startup get roughly 150 seconds before the pod is judged |
| `livenessProbe` | `/health/live` | Restarts a wedged process |
| `readinessProbe` | `/health/ready` | Removes the pod from Service endpoints without restarting it |

Splitting live from ready is what lets a pod whose dependencies are briefly unavailable drop out of
rotation instead of entering a restart loop.

## Local usage

```bash
helm dependency build
helm lint . -f base.values.yaml -f lcl.values.yaml
helm template test . -f base.values.yaml -f lcl.values.yaml
helm install agent-api . -f base.values.yaml -f lcl.values.yaml
```

The values files layer: `base` first, then exactly one environment file. Pass them to `helm lint`
too: a bare `helm lint .` fails on a nil pointer, because there is no `values.yaml` for it to fall
back on.

> The chart must be published to the chart registry by CI before FluxCD can reconcile it. Pushing
> chart source to git is not enough.

## License

[Elastic License 2.0](./LICENSE) — source-available; not OSI open source.
