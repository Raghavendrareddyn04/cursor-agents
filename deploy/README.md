# Sunny production deployment (VPS)

This folder is scaffolded by **Rajesh** (`deployment-platform-agent`) and completed by the deployment pipeline agents. It is the single source of truth for **Minikube + Grafana** production hosting.

## Topology

```
Internet
   │
   ▼
Host Nginx (TLS) ──► PM2 frontend (static SPA)
   │                      │
   │ /api                 └── VITE_API_URL → https://<domain>/api
   ▼
Minikube NodePort (gateway :30080)
   │
   ├── JHipster Gateway pod
   ├── Microservice pods (ClusterIP, distinct ports)
   ├── JHipster Registry pod
   │
Host PostgreSQL ◄── datasource from pods (not public)

Minikube observability namespace
   ├── Prometheus (scrapes /management/prometheus)
   └── Grafana (dashboards + Sunny progress.json panel)
```

## Directory layout

| Path | Status | Purpose |
|------|--------|---------|
| `minikube/` | **On disk** | Namespace, resource quota, kustomization, `service-template.yaml` |
| `minikube/deployment-*.yaml`, `service-*.yaml`, `servicemonitor-*.yaml` | **Created by Manoj (#21)** | Per-microservice manifests copied from `service-template.yaml` |
| `helm/` | **On disk** | `kube-prometheus-stack-values.yaml` (Grafana + Prometheus) |
| `grafana/provisioning/` | **On disk** | Datasources + dashboards as code |
| `nginx/` | **Created by Asha (#22)** | Host-level Nginx site config (TLS, `/api`, `/grafana`) |
| `pm2/` | **Created by Asha (#22)** | PM2 ecosystem file for the static frontend |
| `scripts/` | **On disk** | `provision.sh`, `sync-secrets.sh`, `health-check.sh` |
| `port-map.md` | **On disk** | Authoritative port matrix — Rajesh seeds, Manoj completes, Om verifies |

Before the first Sunny deploy run, `minikube/` may look sparse (only base files) — that is expected. Manoj and Asha add the per-service and edge configs during stages #21–#22.

## Operator commands

```bash
# Platform (Rajesh) — order matters
kubectl apply -f deploy/minikube/namespace.yaml
kubectl apply -f deploy/minikube/resource-quota.yaml
./deploy/scripts/sync-secrets.sh   # grafana-admin secret before Helm
minikube start --cpus=4 --memory=8192 --driver=docker
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability -f deploy/helm/kube-prometheus-stack-values.yaml

# Secrets (never commit values)
./deploy/scripts/sync-secrets.sh   # re-run after Lakshmi sets POSTGRES_PASSWORD

# Backend (Manoj)
eval $(minikube docker-env)
kubectl apply -k deploy/minikube/

# Verify (Om)
./deploy/scripts/health-check.sh
```

## Host PostgreSQL from Minikube

Pods use **`host.min.internal:5432`** (docker driver). See `deploy/port-map.md`. Lakshmi sets `POSTGRES_HOST`; `sync-secrets.sh` wires `SPRING_DATASOURCE_URL`.

## Grafana & Sunny progress

- **Infra/JVM:** Prometheus datasource → JHipster Micrometer metrics on `/management/prometheus`.
- **Pipeline progress:** Grafana Infinity/JSON datasource → `https://<domain>/progress.json` (no-store).
- **Dashboards:** `grafana/provisioning/dashboards/sunny/sunny-deployment.json`

Credentials: `GRAFANA_URL`, `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` in project root `.env` only.

## Production rules

- No secrets in git; use `.env` + `kubectl create secret`.
- Every microservice: liveness + readiness + startup probes, resource limits, distinct port.
- Gateway only exposed via Nginx → NodePort; internal services ClusterIP only.
- TLS on host Nginx; no self-signed certs in production.
