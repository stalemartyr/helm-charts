#!/bin/bash

# NFS Directory Setup Script
# Creates required directories on NFS server for monitoring stack
# NFS Server: 192.168.254.10
# Base Path: /CLUSTER

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NFS_SERVER="192.168.254.10"
NFS_BASE="/CLUSTER"

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}NFS Directory Setup${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "NFS Server: $NFS_SERVER"
echo "Base Path: $NFS_BASE"
echo ""
echo "This script will create the following directories on your NFS server:"
echo "  - ${NFS_BASE}/prometheus"
echo "  - ${NFS_BASE}/alertmanager-0"
echo "  - ${NFS_BASE}/alertmanager-1"
echo "  - ${NFS_BASE}/grafana"
echo "  - ${NFS_BASE}/loki"
echo ""
echo -e "${YELLOW}NOTE: You need SSH access to the NFS server to run this script${NC}"
echo ""
read -p "Continue? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi

# Create directories on NFS server
echo -e "${YELLOW}[INFO]${NC} Creating directories on NFS server..."

ssh root@${NFS_SERVER} << 'ENDSSH'
# Create directories
mkdir -p /CLUSTER/prometheus
mkdir -p /CLUSTER/alertmanager-0
mkdir -p /CLUSTER/alertmanager-1
mkdir -p /CLUSTER/grafana
mkdir -p /CLUSTER/loki

# Set permissions (adjust UID/GID as needed for your environment)
# Prometheus runs as UID 1000
# Grafana runs as UID 472
# Loki runs as UID 10001
chmod 777 /CLUSTER/prometheus
chmod 777 /CLUSTER/alertmanager-0
chmod 777 /CLUSTER/alertmanager-1
chmod 777 /CLUSTER/grafana
chmod 777 /CLUSTER/loki

# Verify
ls -la /CLUSTER/
ENDSSH

echo -e "${GREEN}[SUCCESS]${NC} NFS directories created successfully!"
echo ""
echo "Next steps:"
echo "  1. Apply PersistentVolumes: kubectl apply -f prometheus-pv.yaml"
echo "  2. Verify PVs: kubectl get pv"
echo "  3. Deploy monitoring stack: ./deploy.sh"
