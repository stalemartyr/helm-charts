# Monitoring Stack

Complete observability stack for Kubernetes with **Prometheus**, **Grafana**, **Loki**, and **Promtail**.

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| **Prometheus** | Metrics collection & storage | 9090 |
| **Grafana** | Visualization & dashboards | 3000 |
| **Loki** | Log aggregation | 3100 |
| **Promtail** | Log collection agent | 3101 |
| **Alertmanager** | Alert routing & notification | 9093 |
| **Blackbox Exporter** | Endpoint probing | 9115 |

## Prerequisites

```bash
# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## Installation

### Option 1: Separate Deployments (Recommended)

Deploy each stack separately for better control:

```bash
# 1. Install Prometheus Stack (Prometheus + Grafana + Alertmanager)
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f kube-prometheus-stack-values.yaml

# 2. Install Loki Stack (Loki + Promtail)
helm install loki grafana/loki-stack \
  --namespace monitoring \
  -f loki-stack-values.yaml
```

### Option 2: Quick Install (All at Once)

```bash
# Install everything in one command
kubectl create namespace monitoring
helm install prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring -f kube-prometheus-stack-values.yaml
helm install loki grafana/loki-stack -n monitoring -f loki-stack-values.yaml
```

## Upgrade

```bash
# Upgrade Prometheus Stack
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kube-prometheus-stack-values.yaml

# Upgrade Loki Stack
helm upgrade loki grafana/loki-stack \
  -n monitoring \
  -f loki-stack-values.yaml
```

## Uninstall

```bash
helm uninstall prometheus-stack -n monitoring
helm uninstall loki -n monitoring
```

## Access Services

### Grafana Dashboard

```bash
# Get Grafana password (if not set in values.yaml)
kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Port forward to access locally
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Access at: http://localhost:3000
# Username: admin
# Password: St4l3M4rtyr1992 (or retrieved from secret)
```

### Prometheus UI

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Access at: http://localhost:9090
```

### Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093

# Access at: http://localhost:9093
```

### Loki (Query API)

```bash
kubectl port-forward -n monitoring svc/loki 3100:3100

# Query logs via API:
curl -G -s "http://localhost:3100/loki/api/v1/query" --data-urlencode 'query={namespace="default"}'
```

## Configuration Details

### Prometheus Configuration

- **Retention**: 15 days
- **Storage**: 50GB PVC
- **Replicas**: 1
- **Service Monitors**: Auto-discover all ServiceMonitors

### Grafana Configuration

- **Admin Password**: `St4l3M4rtyr1992` (change in values.yaml)
- **Service Type**: LoadBalancer
- **Persistence**: 10GB PVC
- **Data Sources**:
  - Prometheus (auto-configured)
  - Loki (configured at `http://loki:3100`)

### Loki Configuration

- **Retention**: 14 days (336 hours)
- **Storage**: 50GB PVC
- **Max Query Length**: 30 days (721 hours)
- **Ingestion Rate**: 10MB/s (burst: 20MB/s)

### Promtail Configuration

- **Logs Collected**:
  - All Kubernetes pod logs
  - System logs from `/var/log`
- **Labels Added**:
  - namespace
  - pod
  - container
  - app

### Alertmanager Configuration

- **Email Notifications**: Configured for `jimbertamante@gmail.com`
- **Replicas**: 2 (HA)
- **SMTP**: `137.184.240.106:587`

## Default Dashboards

Grafana comes pre-configured with these dashboards:

1. **Prometheus Stats** (ID: 2)
2. **Kubernetes Cluster Monitoring** (ID: 7249)
3. **Node Exporter Full** (ID: 1860)
4. **Loki Dashboard** (ID: 13639)

## Creating Service Monitors

To monitor your applications, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
```

## Querying Logs in Grafana

Use LogQL to query logs:

```logql
# All logs from a namespace
{namespace="default"}

# Logs containing "error"
{namespace="default"} |= "error"

# Logs from specific app
{app="my-app"}

# JSON parsing
{app="my-app"} | json | level="error"
```

## Querying Metrics in Grafana

Use PromQL to query metrics:

```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)

# Memory usage
sum(container_memory_usage_bytes) by (pod)

# HTTP request rate
rate(http_requests_total[5m])
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n monitoring
```

### View Logs

```bash
# Prometheus
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus

# Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Loki
kubectl logs -n monitoring -l app=loki

# Promtail
kubectl logs -n monitoring -l app=promtail
```

### Common Issues

**Promtail not collecting logs:**
- Check node permissions for `/var/log` and `/var/lib/docker/containers`
- Verify DaemonSet is running on all nodes: `kubectl get ds -n monitoring`

**Loki disk full:**
- Increase retention period in values.yaml
- Add more storage to PVC

**Grafana can't connect to Loki:**
- Verify Loki service: `kubectl get svc -n monitoring loki`
- Check Loki URL in Grafana data source: `http://loki:3100`

## Security Considerations

⚠️ **Important**: The values files contain sensitive information:

1. **Change default passwords**:
   - Grafana admin password
   - SMTP credentials

2. **Use Kubernetes secrets** instead of plain text:
```bash
kubectl create secret generic smtp-credentials \
  --from-literal=username='noreply@jimbertamante.com' \
  --from-literal=password='your-password' \
  -n monitoring
```

3. **Enable authentication**:
   - Set `auth_enabled: true` in Loki config
   - Configure Grafana authentication (LDAP, OAuth, etc.)

## Monitoring Your Monitoring

Monitor the health of your monitoring stack:

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Visit: http://localhost:9090/targets

# Check ServiceMonitors
kubectl get servicemonitors -n monitoring
```

## Resources & Documentation

- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Loki](https://grafana.com/docs/loki/latest/)
- [Promtail](https://grafana.com/docs/loki/latest/clients/promtail/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
