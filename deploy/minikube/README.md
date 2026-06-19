# Minikube manifests (`sunny-prod`)

Rajesh applies namespaces and quotas; Manoj adds Deployments, Services, and ServiceMonitors per microservice.

```bash
kubectl apply -f deploy/minikube/namespace.yaml
kubectl apply -f deploy/minikube/resource-quota.yaml
# After Manoj adds service manifests:
kubectl apply -k deploy/minikube/
```

## Pod → host PostgreSQL

JHipster pods use the **host** database (Lakshmi), not in-cluster Postgres:

- JDBC host: `host.min.internal` (Minikube docker driver)
- See `deploy/port-map.md` and `deployment-database-summary.md`

## Prometheus scrape

Each Deployment pod template should include:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: /management/prometheus
    prometheus.io/port: "8080"
```

Plus a `ServiceMonitor` CR labeled for kube-prometheus-stack.
