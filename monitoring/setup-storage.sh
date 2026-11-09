#!/bin/bash

# Storage Setup Script for Monitoring Stack
# Creates directories and PersistentVolumes for Prometheus, Alertmanager, and Grafana

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
STORAGE_BASE="/mnt/data"
NAMESPACE="monitoring"

print_header() {
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}================================${NC}"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

create_directories_on_nodes() {
    print_header "Creating Storage Directories"

    # Get all nodes
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

    for NODE in $NODES; do
        print_info "Creating directories on node: $NODE"

        # Create directories via SSH or kubectl exec
        # Option 1: Using SSH (if you have SSH access)
        # ssh $NODE "sudo mkdir -p ${STORAGE_BASE}/{prometheus,alertmanager-0,alertmanager-1,grafana} && sudo chmod 777 ${STORAGE_BASE}/*"

        # Option 2: Using kubectl debug (for RKE2/K3s)
        kubectl debug node/$NODE -it --image=busybox -- sh -c "
            chroot /host sh -c '
                mkdir -p ${STORAGE_BASE}/prometheus
                mkdir -p ${STORAGE_BASE}/alertmanager-0
                mkdir -p ${STORAGE_BASE}/alertmanager-1
                mkdir -p ${STORAGE_BASE}/grafana
                chmod 777 ${STORAGE_BASE}/prometheus
                chmod 777 ${STORAGE_BASE}/alertmanager-0
                chmod 777 ${STORAGE_BASE}/alertmanager-1
                chmod 777 ${STORAGE_BASE}/grafana
            '
        " 2>/dev/null || print_error "Failed to create directories on $NODE"

        print_success "Directories created on $NODE"
    done
}

apply_persistent_volumes() {
    print_header "Creating PersistentVolumes"

    if [ ! -f "prometheus-pv.yaml" ]; then
        print_error "prometheus-pv.yaml not found!"
        exit 1
    fi

    kubectl apply -f prometheus-pv.yaml
    print_success "PersistentVolumes created"
}

verify_pvs() {
    print_header "Verifying PersistentVolumes"

    echo ""
    kubectl get pv
    echo ""

    AVAILABLE_PVS=$(kubectl get pv --no-headers 2>/dev/null | grep Available | wc -l)
    if [ "$AVAILABLE_PVS" -ge 4 ]; then
        print_success "All PersistentVolumes are available"
    else
        print_error "Some PersistentVolumes are not available"
    fi
}

show_next_steps() {
    print_header "Next Steps"

    echo ""
    echo "1. Verify PVs are available:"
    echo "   kubectl get pv"
    echo ""
    echo "2. Deploy/Upgrade the monitoring stack:"
    echo "   ./deploy.sh"
    echo "   OR"
    echo "   helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \\"
    echo "     -n monitoring -f kube-prometheus-stack-values.yaml"
    echo ""
    echo "3. Check PVCs are bound:"
    echo "   kubectl get pvc -n monitoring"
    echo ""
    echo "4. Monitor pod status:"
    echo "   kubectl get pods -n monitoring -w"
    echo ""
}

# Main execution
main() {
    print_header "Storage Setup for Monitoring Stack"

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    # Confirm action
    echo -e "${YELLOW}This will create storage directories on all nodes at: ${STORAGE_BASE}${NC}"
    echo -e "${YELLOW}WARNING: This requires node access and will run privileged operations.${NC}"
    echo ""
    read -p "Continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Setup cancelled"
        exit 0
    fi

    create_directories_on_nodes
    apply_persistent_volumes
    verify_pvs
    show_next_steps

    print_success "Storage setup complete!"
}

# Run main function
main
