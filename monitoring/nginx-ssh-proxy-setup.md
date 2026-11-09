# Nginx SSH Proxy Setup Guide

## Overview

Nginx can proxy SSH connections using the **stream module** (Layer 4 TCP/UDP proxy). This is useful for:
- Load balancing SSH across multiple servers
- Exposing internal SSH servers through a single entry point
- Port forwarding and NAT traversal
- Adding monitoring/logging to SSH connections

## Prerequisites

### Check if Stream Module is Available

```bash
nginx -V 2>&1 | grep -o with-stream
```

If nothing is returned, you need to install the stream module.

### Install Stream Module

**Debian/Ubuntu:**
```bash
sudo apt-get install libnginx-mod-stream
```

**CentOS/RHEL:**
```bash
sudo yum install nginx-mod-stream
```

**Or compile from source with:**
```bash
./configure --with-stream --with-stream_ssl_module
make && make install
```

## Basic Setup

### 1. Create Configuration File

**Option A: Include in main nginx.conf**
```bash
sudo nano /etc/nginx/nginx.conf
```

Add the stream block at the **top level** (NOT inside http block):
```nginx
stream {
    upstream ssh_backend {
        server 192.168.254.5:22;
    }

    server {
        listen 2222;
        proxy_pass ssh_backend;
        proxy_timeout 3600s;
    }
}

http {
    # Your existing HTTP configuration
}
```

**Option B: Separate file (recommended)**
```bash
sudo nano /etc/nginx/stream.conf
```

Then include it in `/etc/nginx/nginx.conf`:
```nginx
include /etc/nginx/stream.conf;

http {
    # Your existing HTTP configuration
}
```

### 2. Test Configuration

```bash
sudo nginx -t
```

### 3. Reload Nginx

```bash
sudo systemctl reload nginx
```

### 4. Test SSH Connection

```bash
# Connect through proxy
ssh -p 2222 user@nginx-server-ip

# Should connect to the backend server at 192.168.254.5:22
```

## Common Use Cases

### Use Case 1: Proxy Standard SSH Port (22)

**Important:** Nginx needs to bind to port 22, which requires root or CAP_NET_BIND_SERVICE capability.

```nginx
stream {
    upstream ssh_backend {
        server 192.168.254.5:22;
    }

    server {
        listen 22;
        proxy_pass ssh_backend;
        proxy_timeout 3600s;
        proxy_connect_timeout 60s;
    }
}
```

**Client usage:**
```bash
ssh user@nginx-server-ip
# No need to specify port - uses default 22
```

### Use Case 2: Multiple SSH Servers (Load Balancing)

```nginx
stream {
    upstream ssh_cluster {
        least_conn;  # Use least connections
        server 192.168.1.101:22;
        server 192.168.1.102:22;
        server 192.168.1.103:22;
    }

    server {
        listen 2222;
        proxy_pass ssh_cluster;
        proxy_timeout 3600s;
    }
}
```

### Use Case 3: Port-Based Routing

Different ports forward to different backend servers:

```nginx
stream {
    server {
        listen 2221;
        proxy_pass 192.168.1.101:22;
        proxy_timeout 3600s;
    }

    server {
        listen 2222;
        proxy_pass 192.168.1.102:22;
        proxy_timeout 3600s;
    }

    server {
        listen 2223;
        proxy_pass 192.168.1.103:22;
        proxy_timeout 3600s;
    }
}
```

**Client usage:**
```bash
ssh -p 2221 user@nginx-ip  # Connects to server 1
ssh -p 2222 user@nginx-ip  # Connects to server 2
ssh -p 2223 user@nginx-ip  # Connects to server 3
```

### Use Case 4: High Availability with Backup

```nginx
stream {
    upstream ssh_ha {
        server 192.168.1.100:22 max_fails=3 fail_timeout=30s;
        server 192.168.1.101:22 backup;
    }

    server {
        listen 2222;
        proxy_pass ssh_ha;
        proxy_timeout 3600s;
    }
}
```

### Use Case 5: Kubernetes Service Proxy

```nginx
stream {
    upstream k8s_ssh {
        # Kubernetes ClusterIP service
        server 10.43.100.50:22;
    }

    server {
        listen 2222;
        proxy_pass k8s_ssh;
        proxy_timeout 3600s;
    }
}
```

## Docker Container Example

**Dockerfile:**
```dockerfile
FROM nginx:alpine

# Install stream module (usually included in official nginx)
RUN rm /etc/nginx/conf.d/default.conf

COPY nginx-ssh-proxy.conf /etc/nginx/nginx.conf

EXPOSE 22 2222

CMD ["nginx", "-g", "daemon off;"]
```

**nginx.conf:**
```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

stream {
    upstream ssh_backend {
        server backend-ssh-server:22;
    }

    server {
        listen 2222;
        proxy_pass ssh_backend;
        proxy_timeout 3600s;
    }
}
```

**Run:**
```bash
docker build -t nginx-ssh-proxy .
docker run -d -p 2222:2222 --name ssh-proxy nginx-ssh-proxy
```

## Kubernetes Deployment

**ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-ssh-proxy-config
data:
  nginx.conf: |
    events {}
    stream {
      upstream ssh_backend {
        server my-ssh-service:22;
      }
      server {
        listen 2222;
        proxy_pass ssh_backend;
        proxy_timeout 3600s;
      }
    }
```

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-ssh-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-ssh-proxy
  template:
    metadata:
      labels:
        app: nginx-ssh-proxy
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 2222
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
      volumes:
      - name: config
        configMap:
          name: nginx-ssh-proxy-config
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-ssh-proxy
spec:
  type: LoadBalancer
  ports:
  - port: 2222
    targetPort: 2222
  selector:
    app: nginx-ssh-proxy
```

## Logging and Monitoring

### Enable Detailed Logging

```nginx
stream {
    log_format ssh_proxy '$remote_addr [$time_local] '
                         '$protocol $status $bytes_sent $bytes_received '
                         '$session_time';

    access_log /var/log/nginx/ssh_access.log ssh_proxy;
    error_log /var/log/nginx/ssh_error.log info;

    # ... server configuration
}
```

### View Logs

```bash
# Access logs
tail -f /var/log/nginx/ssh_access.log

# Error logs
tail -f /var/log/nginx/ssh_error.log
```

## Firewall Configuration

**Allow Nginx SSH proxy port:**
```bash
# UFW
sudo ufw allow 2222/tcp

# firewalld
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --reload

# iptables
sudo iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
```

## Troubleshooting

### Connection Refused

```bash
# Check if Nginx is listening
sudo netstat -tlnp | grep nginx
sudo ss -tlnp | grep nginx

# Check backend is accessible
telnet backend-server 22
```

### Permission Denied (Port 22)

```bash
# Option 1: Run nginx as root (not recommended)
# Option 2: Use setcap
sudo setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx

# Option 3: Use authbind
sudo apt-get install authbind
sudo touch /etc/authbind/byport/22
sudo chmod 500 /etc/authbind/byport/22
sudo chown nginx /etc/authbind/byport/22
```

### Timeout Issues

Increase timeouts:
```nginx
server {
    listen 2222;
    proxy_pass ssh_backend;
    proxy_timeout 7200s;        # 2 hours
    proxy_connect_timeout 120s;  # 2 minutes
}
```

### Check Nginx Configuration

```bash
sudo nginx -t -c /etc/nginx/nginx.conf
```

## Security Considerations

1. **Rate Limiting**: Prevent brute force attacks
```nginx
stream {
    limit_conn_zone $binary_remote_addr zone=ssh_conn:10m;

    server {
        listen 2222;
        limit_conn ssh_conn 5;  # Max 5 connections per IP
        proxy_pass ssh_backend;
    }
}
```

2. **IP Whitelisting**: Restrict access
```nginx
stream {
    geo $allowed_ip {
        default 0;
        192.168.1.0/24 1;
        10.0.0.0/8 1;
    }

    server {
        listen 2222;
        if ($allowed_ip = 0) {
            return 403;
        }
        proxy_pass ssh_backend;
    }
}
```

3. **Fail2Ban Integration**: Monitor logs
```bash
# /etc/fail2ban/filter.d/nginx-ssh.conf
[Definition]
failregex = ^<HOST> \[.*\] TCP 000
```

## Performance Tuning

```nginx
worker_processes auto;

events {
    worker_connections 10000;
    use epoll;
}

stream {
    upstream ssh_backend {
        server backend:22;
        keepalive 100;
    }

    server {
        listen 2222 so_keepalive=on;
        proxy_pass ssh_backend;
        proxy_socket_keepalive on;
    }
}
```

## References

- [Nginx Stream Module Documentation](http://nginx.org/en/docs/stream/ngx_stream_core_module.html)
- [TCP/UDP Load Balancing](https://docs.nginx.com/nginx/admin-guide/load-balancer/tcp-udp-load-balancer/)
