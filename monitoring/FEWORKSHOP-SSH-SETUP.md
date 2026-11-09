# SSH Proxy Setup for feworkshop.jimbertamante.com

## Overview

This configuration sets up Nginx as an SSH proxy for `feworkshop.jimbertamante.com`, forwarding SSH connections to your backend server.

## Architecture

```
Client (ssh user@feworkshop.jimbertamante.com)
    ↓
Nginx Proxy (feworkshop.jimbertamante.com:22 or :2222)
    ↓
Backend SSH Server (192.168.254.5:22)
```

## Prerequisites

1. **DNS Configuration**: Ensure `feworkshop.jimbertamante.com` points to your Nginx server
2. **Nginx with stream module**: Required for TCP proxying
3. **Backend SSH server**: Running and accessible at `192.168.254.5:22`

## Quick Setup

### Option 1: Using Port 22 (Standard SSH)

**1. Install configuration:**
```bash
sudo cp nginx-feworkshop-ssh-proxy.conf /etc/nginx/nginx.conf
```

**2. Update backend server IP:**
```bash
sudo nano /etc/nginx/nginx.conf
# Change: server 192.168.254.5:22;
# To your actual backend SSH server IP
```

**3. Test configuration:**
```bash
sudo nginx -t
```

**4. Reload Nginx:**
```bash
sudo systemctl reload nginx
```

**5. Connect from client:**
```bash
ssh user@feworkshop.jimbertamante.com
# Uses standard port 22
```

### Option 2: Using Port 2222 (Alternate Port)

If you want to keep port 22 for local SSH on the Nginx server:

**1. Comment out the port 22 listener in the config**
**2. Keep the port 2222 listener active**
**3. Connect from client:**
```bash
ssh -p 2222 user@feworkshop.jimbertamante.com
```

## DNS Configuration

Ensure your DNS is configured:

```bash
# Check DNS resolution
dig feworkshop.jimbertamante.com

# Or
nslookup feworkshop.jimbertamante.com
```

Should return the IP address of your Nginx proxy server.

## Firewall Configuration

### On Nginx Proxy Server

```bash
# For port 22
sudo ufw allow 22/tcp

# Or for port 2222
sudo ufw allow 2222/tcp

# Check status
sudo ufw status
```

### On Backend SSH Server

Ensure the backend server allows connections from the Nginx proxy:

```bash
# Allow from Nginx proxy IP (e.g., 192.168.254.240)
sudo ufw allow from 192.168.254.240 to any port 22
```

## Testing

### 1. Test Nginx is Listening

```bash
# On Nginx server
sudo netstat -tlnp | grep nginx
# Should show: 0.0.0.0:22 or 0.0.0.0:2222

# Or use ss
sudo ss -tlnp | grep nginx
```

### 2. Test Backend Connectivity

```bash
# From Nginx server, test connection to backend
ssh -p 22 user@192.168.254.5
```

### 3. Test Proxy Connection

```bash
# From client machine
ssh user@feworkshop.jimbertamante.com

# With verbose output to debug
ssh -v user@feworkshop.jimbertamante.com
```

### 4. Check Nginx Logs

```bash
# Access logs
sudo tail -f /var/log/nginx/ssh_access.log

# Error logs
sudo tail -f /var/log/nginx/ssh_error.log
```

## Docker Deployment

**docker-compose.yml:**
```yaml
version: '3.8'
services:
  nginx-ssh-proxy:
    image: nginx:alpine
    container_name: feworkshop-ssh-proxy
    ports:
      - "22:22"      # Standard SSH port
      - "2222:2222"  # Alternate SSH port
    volumes:
      - ./nginx-feworkshop-ssh-proxy.conf:/etc/nginx/nginx.conf:ro
      - ./logs:/var/log/nginx
    restart: unless-stopped
    networks:
      - backend

networks:
  backend:
    driver: bridge
```

**Start:**
```bash
docker-compose up -d
```

**View logs:**
```bash
docker-compose logs -f nginx-ssh-proxy
```

## Kubernetes Deployment

**ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: feworkshop-ssh-proxy-config
  namespace: default
data:
  nginx.conf: |
    events {}
    stream {
      upstream feworkshop_ssh {
        server 192.168.254.5:22;
      }
      server {
        listen 22;
        proxy_pass feworkshop_ssh;
        proxy_timeout 3600s;
        proxy_connect_timeout 60s;
        proxy_socket_keepalive on;
      }
    }
```

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: feworkshop-ssh-proxy
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: feworkshop-ssh-proxy
  template:
    metadata:
      labels:
        app: feworkshop-ssh-proxy
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 22
          name: ssh
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
      volumes:
      - name: config
        configMap:
          name: feworkshop-ssh-proxy-config
```

**Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: feworkshop-ssh-proxy
  namespace: default
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.254.240  # Your external IP
  ports:
  - port: 22
    targetPort: 22
    protocol: TCP
    name: ssh
  selector:
    app: feworkshop-ssh-proxy
```

**Deploy:**
```bash
kubectl apply -f feworkshop-ssh-configmap.yaml
kubectl apply -f feworkshop-ssh-deployment.yaml
kubectl apply -f feworkshop-ssh-service.yaml
```

## Client SSH Config

For easier access, add to `~/.ssh/config`:

```bash
Host feworkshop
    HostName feworkshop.jimbertamante.com
    Port 22  # Or 2222 if using alternate port
    User your-username
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

**Connect:**
```bash
ssh feworkshop
```

## Security Best Practices

### 1. Rate Limiting

Add to stream block in nginx.conf:

```nginx
stream {
    limit_conn_zone $binary_remote_addr zone=ssh_conn:10m;

    server {
        listen 22;
        limit_conn ssh_conn 10;  # Max 10 connections per IP
        proxy_pass feworkshop_ssh;
    }
}
```

### 2. IP Whitelisting

Only allow from specific IPs:

```nginx
stream {
    geo $allowed {
        default 0;
        192.168.1.0/24 1;      # Office network
        203.0.113.0/24 1;      # Another trusted network
    }

    server {
        listen 22;
        if ($allowed = 0) {
            return 403;
        }
        proxy_pass feworkshop_ssh;
    }
}
```

### 3. Fail2Ban

Monitor failed attempts:

**/etc/fail2ban/jail.local:**
```ini
[nginx-ssh]
enabled = true
port = ssh
logpath = /var/log/nginx/ssh_error.log
maxretry = 5
bantime = 3600
```

## Monitoring

### Prometheus Metrics

If using nginx-prometheus-exporter, you can expose metrics:

```yaml
# Add to your ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: feworkshop-ssh-proxy
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: nginx-exporter
  endpoints:
    - port: metrics
      interval: 30s
```

### Grafana Dashboard

Import dashboard ID **12708** for Nginx stream metrics.

### Log Monitoring with Loki

Promtail can collect Nginx SSH logs:

```yaml
# promtail scrape config
- job_name: nginx-ssh
  static_configs:
    - targets:
        - localhost
      labels:
        job: nginx-ssh
        __path__: /var/log/nginx/ssh_*.log
```

Query in Grafana:
```logql
{job="nginx-ssh"} |= "error"
```

## Troubleshooting

### Connection Refused

```bash
# Check Nginx is running
sudo systemctl status nginx

# Check if port is listening
sudo netstat -tlnp | grep 22
```

### Permission Denied (Port 22)

```bash
# Give Nginx permission to bind to port 22
sudo setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx

# Restart Nginx
sudo systemctl restart nginx
```

### Timeout Connecting to Backend

```bash
# Test backend connectivity from Nginx server
telnet 192.168.254.5 22

# Check firewall rules on backend
sudo ufw status
```

### Check Configuration

```bash
# Test syntax
sudo nginx -t

# View running config
sudo nginx -T
```

## Backup and Rollback

```bash
# Backup current config
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d)

# Rollback if needed
sudo cp /etc/nginx/nginx.conf.backup.YYYYMMDD /etc/nginx/nginx.conf
sudo systemctl reload nginx
```

## Load Testing

Test proxy performance:

```bash
# Simple connection test
for i in {1..100}; do
  ssh -o ConnectTimeout=5 user@feworkshop.jimbertamante.com "echo test $i"
done
```

## Maintenance

### Reload Configuration (Zero Downtime)

```bash
sudo nginx -t && sudo nginx -s reload
```

### View Active Connections

```bash
sudo ss -tn | grep ':22'
```

### Rotate Logs

```bash
sudo logrotate -f /etc/logrotate.d/nginx
```

## Summary

**To connect to feworkshop backend via SSH:**

```bash
# Standard port
ssh user@feworkshop.jimbertamante.com

# Alternate port
ssh -p 2222 user@feworkshop.jimbertamante.com

# With SSH config alias
ssh feworkshop
```

All SSH traffic will be transparently proxied to `192.168.254.5:22`.
