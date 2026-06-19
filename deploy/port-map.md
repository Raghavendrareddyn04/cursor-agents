# Sunny production port map

Authoritative port matrix for Minikube + host edge. **Rajesh** seeds this draft; **Manoj** completes rows per microservice from `backend-summary.md` / `architecture-summary.md`. **Om** verifies live state matches this file.

| Service | Container port | Service port | NodePort | Actuator health | Notes |
|---------|----------------|--------------|----------|-----------------|-------|
| jhipster-registry | 8761 | 8761 | 30761 | `/management/health` | Eureka/registry |
| gateway | 8080 | 8080 | 30080 | `/management/health` | Only app entry from Nginx `/api` |
| _{microservice}_ | 808x | 808x | — | `/management/health` | ClusterIP only; no public NodePort |
| grafana (observability) | 3000 | 80 | 30300 | `/api/health` | Asha proxies `https://<domain>/grafana` |
| prometheus (observability) | 9090 | 9090 | — | `/-/healthy` | Internal only |
| postgresql (host) | 5432 | 5432 | — | — | `host.min.internal:5432` from pods |
| frontend (PM2 host) | — | — | 3000 | `/` | Asha: `https://<domain>/` |

## Host PostgreSQL from Minikube pods

Use **`host.min.internal`** (Minikube docker driver) in JDBC URLs:

```
jdbc:postgresql://host.min.internal:5432/{database}
```

Lakshmi documents the chosen host alias in `deployment-database-summary.md`. Manoj wires `SPRING_DATASOURCE_URL` via `sync-secrets.sh`.
