# Storage Setup for Monitoring Stack

This guide explains how to set up persistent storage for Prometheus, Alertmanager, and Grafana.

## Overview

The monitoring stack requires persistent storage for:
- **Prometheus**: 50GB (metrics data)
- **Alertmanager**: 10GB × 2 replicas (alert state)
- **Grafana**: 10GB (dashboards and settings)

## Storage Options

### Option 1: Automated Setup (Recommended for HostPath)

Use the provided script to automatically create directories and PVs:

```bash
export KUBECONFIG=~/.kube/rke2.yaml

# Edit prometheus-pv.yaml if needed to configure storage paths
./setup-storage.sh
```

### Option 2: Manual Setup

#### Step 1: Create Storage Directories on Nodes

For **hostPath** storage, create directories on your nodes:

```bash
# SSH to each node and run:
sudo mkdir -p /mnt/data/prometheus
sudo mkdir -p /mnt/data/alertmanager-0
sudo mkdir -p /mnt/data/alertmanager-1
sudo mkdir -p /mnt/data/grafana

# Set permissions
sudo chmod 777 /mnt/data/*
```

#### Step 2: Configure Storage Type

Edit `prometheus-pv.yaml` and choose your storage type:

**For HostPath (single node, testing):**
```yaml
storageClassName: manual
hostPath:
  path: /mnt/data/prometheus
  type: DirectoryOrCreate
```

**For Local Storage (production):**
```yaml
storageClassName: local-storage
local:
  path: /data/prometheus
nodeAffinity:
  required:
    nodeSelectorTerms:
    - matchExpressions:
      - key: kubernetes.io/hostname
        operator: In
        values:
        - your-node-name
```

**For NFS:**
```yaml
storageClassName: nfs
nfs:
  server: 192.168.1.100
  path: /exports/prometheus
```

#### Step 3: Apply PersistentVolumes

```bash
kubectl apply -f prometheus-pv.yaml
```

#### Step 4: Verify PVs

```bash
kubectl get pv

# Should show:
# NAME                       CAPACITY   STATUS      STORAGECLASS
# prometheus-data-pv         50Gi       Available   manual
# alertmanager-data-pv-0     10Gi       Available   manual
# alertmanager-data-pv-1     10Gi       Available   manual
# grafana-data-pv            10Gi       Available   manual
```

## Deploy with Storage Enabled

The storage configuration is already enabled in `kube-prometheus-stack-values.yaml`:

```bash
# Deploy new installation
./deploy.sh

# OR upgrade existing installation
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kube-prometheus-stack-values.yaml
```

## Verify Storage is Working

### Check PVCs are Bound

```bash
kubectl get pvc -n monitoring

# Should show Bound status:
# NAME                                                            STATUS   VOLUME
# prometheus-prometheus-stack-kube-prom-prometheus-db-...-0       Bound    prometheus-data-pv
# storage-prometheus-stack-kube-prom-alertmanager-0               Bound    alertmanager-data-pv-0
# storage-prometheus-stack-kube-prom-alertmanager-1               Bound    alertmanager-data-pv-1
# prometheus-stack-grafana                                        Bound    grafana-data-pv
```

### Check Pods are Running

```bash
kubectl get pods -n monitoring

# All pods should be Running
```

### Verify Data Persistence

```bash
# Check Prometheus data directory
kubectl exec -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -c prometheus -- ls -lah /prometheus

# Check if data survives pod restart
kubectl delete pod -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0
kubectl get pods -n monitoring -w  # Wait for pod to restart
# Data should still be present after restart
```

## Storage Sizing Guide

Adjust sizes based on your needs:

| Component | Default | Light Usage | Heavy Usage |
|-----------|---------|-------------|-------------|
| Prometheus | 50Gi | 20Gi | 100Gi+ |
| Alertmanager | 10Gi | 5Gi | 20Gi |
| Grafana | 10Gi | 5Gi | 20Gi |

Edit the sizes in `kube-prometheus-stack-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 100Gi  # Adjust here
```

## Using Dynamic Provisioning

If your cluster has a StorageClass that supports dynamic provisioning (like `longhorn`, `ceph-rbd`, or cloud providers):

### 1. Remove Manual PVs

```bash
# Don't apply prometheus-pv.yaml
```

### 2. Update Values File

Change `storageClassName` in `kube-prometheus-stack-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn  # or your StorageClass name
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
```

### 3. Deploy

```bash
./deploy.sh
```

PVCs will automatically create PVs using the StorageClass.

## Troubleshooting

### PVC Stuck in Pending

```bash
kubectl describe pvc -n monitoring <pvc-name>

# Common issues:
# - No PV available with matching size/storageClassName
# - PV already bound to another PVC
# - StorageClass not found
```

**Fix:**
- Ensure PV exists: `kubectl get pv`
- Check storageClassName matches
- Verify node has enough disk space

### Pod Stuck in ContainerCreating

```bash
kubectl describe pod -n monitoring <pod-name>

# Look for events like:
# - "Unable to attach or mount volumes"
# - "MountVolume.SetUp failed"
```

**Fix:**
- Check directory exists on node
- Verify permissions: `chmod 777 /mnt/data/*`
- Check SELinux/AppArmor if enabled

### Data Not Persisting

```bash
# Verify PVC is actually bound
kubectl get pvc -n monitoring

# Check mount in pod
kubectl exec -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -c prometheus -- df -h | grep prometheus
```

## Backup and Restore

### Backup Prometheus Data

```bash
# Copy data from PV
kubectl cp monitoring/prometheus-prometheus-stack-kube-prom-prometheus-0:/prometheus ./prometheus-backup

# Or if using hostPath/local, directly from node:
sudo tar -czf prometheus-backup.tar.gz /mnt/data/prometheus
```

### Restore Prometheus Data

```bash
# Stop Prometheus
kubectl scale statefulset -n monitoring prometheus-prometheus-stack-kube-prom-prometheus --replicas=0

# Restore data (on node if using hostPath)
sudo rm -rf /mnt/data/prometheus/*
sudo tar -xzf prometheus-backup.tar.gz -C /

# Restart Prometheus
kubectl scale statefulset -n monitoring prometheus-prometheus-stack-kube-prom-prometheus --replicas=1
```

## Cleanup

To remove all persistent storage:

```bash
# Delete PVCs (this will NOT delete PVs with Retain policy)
kubectl delete pvc --all -n monitoring

# Delete PVs
kubectl delete pv prometheus-data-pv alertmanager-data-pv-0 alertmanager-data-pv-1 grafana-data-pv

# Remove data from nodes (if using hostPath)
# SSH to each node:
sudo rm -rf /mnt/data/prometheus
sudo rm -rf /mnt/data/alertmanager-*
sudo rm -rf /mnt/data/grafana
```

## References

- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Prometheus Storage](https://prometheus.io/docs/prometheus/latest/storage/)
- [Grafana Storage](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#data-path)
