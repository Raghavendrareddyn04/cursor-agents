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

| Path | Purpose |
|------|---------|
| `minikube/` | K8s Deployments, Services, ConfigMaps, ServiceMonitors, secrets templates |
| `helm/` | `kube-prometheus-stack-values.yaml` and other Helm values |
| `grafana/provisioning/` | Datasources + dashboards as code |
| `nginx/` | Host-level Nginx config (Asha) |
| `pm2/` | Frontend ecosystem file (Asha) |
| `scripts/` | `provision.sh`, `sync-secrets.sh`, health-check scripts |
| `port-map.md` | Authoritative port matrix — Om verifies against this |

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
