# Blackbox Exporter Setup Guide

The Blackbox Exporter allows you to probe HTTP/HTTPS/TCP/ICMP endpoints and collect metrics about their availability and response times.

## Quick Install

```bash
export KUBECONFIG=~/.kube/rke2.yaml

helm install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  -n monitoring \
  -f blackbox-exporter-values.yaml
```

Or use the deploy script (which installs everything including blackbox):

```bash
./deploy.sh
```

## Verify Installation

```bash
# Check pod status
kubectl get pods -n monitoring | grep blackbox

# Check service
kubectl get svc -n monitoring | grep blackbox

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring | grep blackbox
```

## Testing Blackbox Exporter

### 1. Port Forward to Access UI

```bash
kubectl port-forward -n monitoring svc/blackbox-exporter-prometheus-blackbox-exporter 9115:9115
```

Open http://localhost:9115 to see the Blackbox Exporter web interface.

### 2. Manual Probe Test

Test a probe manually via the web interface or curl:

```bash
# HTTP probe
curl "http://localhost:9115/probe?target=https://example.com&module=https_2xx"

# The response will show detailed metrics about the probe
```

### 3. View Metrics in Prometheus

Port forward Prometheus:

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

Query these metrics in Prometheus (http://localhost:9090):

```promql
# Check if target is up (1 = up, 0 = down)
probe_success{job="blackbox-exporter"}

# Response time
probe_duration_seconds{job="blackbox-exporter"}

# HTTP status code
probe_http_status_code{job="blackbox-exporter"}

# SSL certificate expiry
probe_ssl_earliest_cert_expiry{job="blackbox-exporter"}
```

## Adding Your Own Targets

Edit `blackbox-exporter-values.yaml` and add targets to the `serviceMonitor.targets` section:

```yaml
serviceMonitor:
  targets:
    # Your website
    - name: my-website
      url: https://mywebsite.com
      module: https_2xx
      interval: 60s

    # Your API health endpoint
    - name: api-health
      url: https://api.myapp.com/health
      module: https_2xx
      interval: 30s

    # TCP port check
    - name: database-port
      url: db.example.com:5432
      module: tcp_connect
      interval: 30s
```

Then upgrade the release:

```bash
helm upgrade blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  -n monitoring \
  -f blackbox-exporter-values.yaml
```

## Available Probe Modules

The following probe modules are configured:

| Module | Type | Description | Use Case |
|--------|------|-------------|----------|
| `http_2xx` | HTTP | Basic HTTP check | Non-HTTPS websites |
| `https_2xx` | HTTPS | HTTPS check (skip cert verify) | Testing/dev environments |
| `https_2xx_verify` | HTTPS | HTTPS check (verify cert) | Production HTTPS endpoints |
| `http_post_2xx` | HTTP POST | HTTP POST request | API endpoints requiring POST |
| `tcp_connect` | TCP | TCP connection check | Database ports, custom services |
| `icmp` | ICMP | Ping check | Basic network connectivity |
| `dns_check` | DNS | DNS resolution check | DNS availability |

## Creating Alerts for Blackbox Probes

Create a PrometheusRule to alert when endpoints are down:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: blackbox-alerts
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  groups:
    - name: blackbox
      interval: 30s
      rules:
        # Alert when endpoint is down
        - alert: EndpointDown
          expr: probe_success == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Endpoint {{ $labels.target }} is down"
            description: "{{ $labels.target }} has been down for more than 5 minutes"

        # Alert when SSL cert expires soon
        - alert: SSLCertExpiringSoon
          expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "SSL certificate expiring soon"
            description: "SSL cert for {{ $labels.target }} expires in {{ $value }} days"

        # Alert on slow response
        - alert: SlowResponse
          expr: probe_duration_seconds > 5
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Slow response from {{ $labels.target }}"
            description: "Response time is {{ $value }}s"
```

Apply it:

```bash
kubectl apply -f blackbox-alerts.yaml
```

## Grafana Dashboard

Import the official Blackbox Exporter dashboard:

1. Go to Grafana (port-forward or LoadBalancer IP)
2. Click **Dashboards** → **Import**
3. Enter dashboard ID: **7587**
4. Select **Prometheus** as data source
5. Click **Import**

This dashboard shows:
- Probe success/failure
- Response times
- SSL certificate expiry
- HTTP status codes

## Common Use Cases

### 1. Monitor Website Availability

```yaml
- name: company-website
  url: https://mycompany.com
  module: https_2xx_verify
  interval: 60s
```

### 2. Monitor API Health

```yaml
- name: api-health-check
  url: https://api.myapp.com/health
  module: https_2xx
  interval: 30s
```

### 3. Monitor Database Port

```yaml
- name: postgres-db
  url: postgres.default.svc.cluster.local:5432
  module: tcp_connect
  interval: 30s
```

### 4. Monitor Internal Services

```yaml
- name: internal-service
  url: http://my-service.default.svc.cluster.local:8080/health
  module: http_2xx
  interval: 30s
```

## Troubleshooting

### Probes Failing with Timeout

Increase timeout in the module configuration:

```yaml
config:
  modules:
    https_2xx:
      prober: http
      timeout: 10s  # Increase from 5s
```

### ICMP Probes Not Working

Ensure the container has `NET_RAW` capability (already configured in values):

```yaml
securityContext:
  capabilities:
    add:
      - NET_RAW
```

### Target Not Appearing in Prometheus

1. Check ServiceMonitor exists: `kubectl get servicemonitor -n monitoring`
2. Check Prometheus targets: http://localhost:9090/targets
3. Check ServiceMonitor has correct label: `release: prometheus-stack`

## Metrics Reference

Key metrics exported by Blackbox Exporter:

```promql
# Probe success (1 = success, 0 = failure)
probe_success

# Total probe duration
probe_duration_seconds

# DNS lookup time
probe_dns_lookup_time_seconds

# Connection time
probe_http_duration_seconds{phase="connect"}

# TLS handshake time
probe_http_duration_seconds{phase="tls"}

# Response time
probe_http_duration_seconds{phase="processing"}

# SSL cert expiry (Unix timestamp)
probe_ssl_earliest_cert_expiry

# HTTP status code
probe_http_status_code

# HTTP protocol version
probe_http_version
```

## Upgrading

```bash
helm repo update
helm upgrade blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  -n monitoring \
  -f blackbox-exporter-values.yaml
```

## Uninstalling

```bash
helm uninstall blackbox-exporter -n monitoring
```

Or use the uninstall script:

```bash
./uninstall.sh
```
