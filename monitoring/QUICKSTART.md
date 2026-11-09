# Monitoring Stack - Quick Start Guide

## TL;DR - Get Up and Running in 5 Minutes

```bash
# 1. Make scripts executable (already done)
chmod +x deploy.sh uninstall.sh

# 2. Deploy everything
./deploy.sh

# 3. Access Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Open http://localhost:3000
# Username: admin
# Password: St4l3M4rtyr1992
```

## What You Get

After running `./deploy.sh`, you'll have:

- **Prometheus** - Collecting metrics from your cluster
- **Grafana** - Beautiful dashboards to visualize everything
- **Loki** - Aggregating all your logs
- **Promtail** - Collecting logs from all pods
- **Alertmanager** - Sending email alerts
- **Node Exporter** - System metrics from each node
- **Kube State Metrics** - Kubernetes cluster metrics
- **Blackbox Exporter** - HTTP/HTTPS endpoint monitoring

## Quick Commands

### Access Services

```bash
# Grafana (http://localhost:3000)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Prometheus (http://localhost:9090)
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Alertmanager (http://localhost:9093)
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093

# Loki (http://localhost:3100)
kubectl port-forward -n monitoring svc/loki 3100:3100
```

### Check Status

```bash
# All pods
kubectl get pods -n monitoring

# All services
kubectl get svc -n monitoring

# All PVCs
kubectl get pvc -n monitoring

# Helm releases
helm list -n monitoring
```

### View Logs

```bash
# Prometheus
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=50

# Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50

# Loki
kubectl logs -n monitoring -l app=loki --tail=50

# Promtail
kubectl logs -n monitoring -l app=promtail --tail=50
```

## Testing Your Setup

### 1. Check Prometheus Targets

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090

# Open in browser: http://localhost:9090/targets
# All targets should show "UP"
```

### 2. Query Metrics in Prometheus

Visit http://localhost:9090/graph and try these queries:

```promql
# Node CPU usage
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod memory usage
sum(container_memory_usage_bytes{container!=""}) by (pod)

# HTTP request rate
rate(http_requests_total[5m])
```

### 3. Check Logs in Grafana

1. Open Grafana: http://localhost:3000
2. Go to **Explore** (compass icon)
3. Select **Loki** as data source
4. Try these queries:

```logql
# All logs from kube-system namespace
{namespace="kube-system"}

# Logs containing "error"
{namespace="default"} |= "error"

# Logs from specific pod
{pod="my-app-xyz"}
```

### 4. View Dashboards

In Grafana, go to **Dashboards** → **Browse** to see:

- Kubernetes Cluster Monitoring
- Node Exporter Full
- Prometheus Stats
- Loki Dashboard

## Monitor Your Own Application

### Step 1: Expose Metrics Endpoint

Your app needs to expose metrics at `/metrics`:

```python
# Python example with Flask
from prometheus_client import Counter, generate_latest

requests_total = Counter('http_requests_total', 'Total requests')

@app.route('/metrics')
def metrics():
    return generate_latest()

@app.route('/')
def index():
    requests_total.inc()
    return 'Hello World'
```

### Step 2: Create Kubernetes Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  selector:
    app: my-app
  ports:
    - name: http
      port: 8080
    - name: metrics  # Important: named port
      port: 9090
```

### Step 3: Create ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  selector:
    matchLabels:
      app: my-app
  namespaceSelector:
    matchNames:
      - default
  endpoints:
    - port: metrics
      interval: 30s
```

Apply it:

```bash
kubectl apply -f servicemonitor.yaml
```

### Step 4: Verify in Prometheus

1. Port forward Prometheus: `kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090`
2. Open http://localhost:9090/targets
3. Find your app in the list
4. Should show "UP"

## Common Issues & Solutions

### Promtail not collecting logs

**Problem**: No logs showing in Loki

**Solution**:
```bash
# Check Promtail pods
kubectl get pods -n monitoring -l app=promtail

# Check Promtail logs
kubectl logs -n monitoring -l app=promtail

# Verify Promtail can reach Loki
kubectl exec -n monitoring -it <promtail-pod> -- wget -O- http://loki:3100/ready
```

### Grafana can't reach Loki

**Problem**: "Bad Gateway" when querying Loki in Grafana

**Solution**:
1. Check Loki is running: `kubectl get pods -n monitoring -l app=loki`
2. Verify Loki service: `kubectl get svc -n monitoring loki`
3. Test from Grafana pod:
```bash
kubectl exec -n monitoring -it <grafana-pod> -- wget -O- http://loki:3100/ready
```

### ServiceMonitor not discovered

**Problem**: Your app doesn't appear in Prometheus targets

**Checklist**:
1. ServiceMonitor has label `release: prometheus-stack`
2. Service has correct label selector
3. Port name matches in Service and ServiceMonitor
4. Namespace is correct
5. Service and endpoints exist:
```bash
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>
```

### High memory usage

**Problem**: Prometheus/Loki using too much memory

**Solution**:
1. Reduce retention period in values.yaml
2. Lower ingestion rate limits
3. Increase resource limits
4. Add more nodes to cluster

## Upgrade Stack

```bash
# Update Helm repos
helm repo update

# Upgrade Prometheus Stack
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kube-prometheus-stack-values.yaml

# Upgrade Loki Stack
helm upgrade loki grafana/loki-stack \
  -n monitoring \
  -f loki-stack-values.yaml
```

## Backup & Restore

### Backup Grafana Dashboards

```bash
# Export all dashboards
kubectl exec -n monitoring <grafana-pod> -- \
  grafana-cli admin export-dashboards > dashboards-backup.json
```

### Backup Prometheus Data

```bash
# Create snapshot
kubectl exec -n monitoring prometheus-stack-kube-prom-prometheus-0 -- \
  promtool tsdb snapshot /prometheus

# Copy snapshot
kubectl cp monitoring/prometheus-stack-kube-prom-prometheus-0:/prometheus/snapshots/<snapshot> ./prometheus-backup
```

## Cleanup

```bash
# Remove everything
./uninstall.sh

# Or manually:
helm uninstall prometheus-stack -n monitoring
helm uninstall loki -n monitoring
kubectl delete namespace monitoring
```

## Next Steps

1. **Customize Dashboards**: Create your own dashboards in Grafana
2. **Add Alerts**: Create PrometheusRules for custom alerts (see `examples-prometheusrules.yaml`)
3. **Monitor More Apps**: Add ServiceMonitors for your applications (see `examples-servicemonitor.yaml`)
4. **Secure Access**: Set up Ingress with TLS for Grafana
5. **Configure RBAC**: Limit access to monitoring resources
6. **Set Up Remote Storage**: Use Thanos or Cortex for long-term metrics storage

## Resources

- Example ServiceMonitors: `examples-servicemonitor.yaml`
- Example PrometheusRules: `examples-prometheusrules.yaml`
- Full Documentation: `README.md`
- Deployment Script: `deploy.sh`
- Uninstall Script: `uninstall.sh`

## Get Help

```bash
# Prometheus docs
open https://prometheus.io/docs/

# Grafana docs
open https://grafana.com/docs/

# Loki docs
open https://grafana.com/docs/loki/

# Check GitHub issues
open https://github.com/prometheus-community/helm-charts/issues
```

---

**Happy Monitoring!** 🎉
