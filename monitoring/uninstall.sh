#!/bin/bash

# Monitoring Stack Uninstall Script
# Removes Prometheus, Grafana, Loki, and Promtail from Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="monitoring"
PROMETHEUS_RELEASE="prometheus-stack"
LOKI_RELEASE="loki"
BLACKBOX_RELEASE="blackbox-exporter"

# Functions
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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

confirm_uninstall() {
    print_header "Uninstall Confirmation"

    echo -e "${RED}WARNING: This will remove all monitoring components and their data!${NC}"
    echo ""
    echo "The following will be removed:"
    echo "  - Prometheus Stack ($PROMETHEUS_RELEASE)"
    echo "  - Loki Stack ($LOKI_RELEASE)"
    echo "  - Blackbox Exporter ($BLACKBOX_RELEASE)"
    echo "  - All PersistentVolumeClaims (if you choose to)"
    echo "  - Namespace '$NAMESPACE' (if you choose to)"
    echo ""

    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
}

uninstall_loki_stack() {
    print_header "Uninstalling Loki Stack"

    if helm list -n $NAMESPACE | grep -q $LOKI_RELEASE; then
        print_info "Uninstalling $LOKI_RELEASE..."
        helm uninstall $LOKI_RELEASE --namespace $NAMESPACE
        print_success "Loki stack uninstalled"
    else
        print_warning "Loki stack not found"
    fi
}

uninstall_blackbox_exporter() {
    print_header "Uninstalling Blackbox Exporter"

    if helm list -n $NAMESPACE | grep -q $BLACKBOX_RELEASE; then
        print_info "Uninstalling $BLACKBOX_RELEASE..."
        helm uninstall $BLACKBOX_RELEASE --namespace $NAMESPACE
        print_success "Blackbox Exporter uninstalled"
    else
        print_warning "Blackbox Exporter not found"
    fi
}

uninstall_prometheus_stack() {
    print_header "Uninstalling Prometheus Stack"

    if helm list -n $NAMESPACE | grep -q $PROMETHEUS_RELEASE; then
        print_info "Uninstalling $PROMETHEUS_RELEASE..."
        helm uninstall $PROMETHEUS_RELEASE --namespace $NAMESPACE
        print_success "Prometheus stack uninstalled"
    else
        print_warning "Prometheus stack not found"
    fi
}

cleanup_pvcs() {
    print_header "Cleaning up PersistentVolumeClaims"

    read -p "Do you want to delete all PVCs in namespace '$NAMESPACE'? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Deleting PVCs..."
        kubectl delete pvc --all -n $NAMESPACE || print_warning "No PVCs found or error deleting"
        print_success "PVCs deleted"
    else
        print_info "Skipping PVC deletion"
    fi
}

cleanup_namespace() {
    print_header "Cleaning up Namespace"

    read -p "Do you want to delete namespace '$NAMESPACE'? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Deleting namespace..."
        kubectl delete namespace $NAMESPACE || print_warning "Error deleting namespace"
        print_success "Namespace deleted"
    else
        print_info "Skipping namespace deletion"
    fi
}

cleanup_crds() {
    print_header "Cleaning up CRDs"

    read -p "Do you want to delete Prometheus Operator CRDs? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warning "This will remove all ServiceMonitors, PodMonitors, PrometheusRules, etc."
        read -p "Are you absolutely sure? (yes/no): " -r
        echo
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Deleting CRDs..."
            kubectl delete crd prometheuses.monitoring.coreos.com || true
            kubectl delete crd prometheusrules.monitoring.coreos.com || true
            kubectl delete crd servicemonitors.monitoring.coreos.com || true
            kubectl delete crd podmonitors.monitoring.coreos.com || true
            kubectl delete crd alertmanagers.monitoring.coreos.com || true
            kubectl delete crd alertmanagerconfigs.monitoring.coreos.com || true
            kubectl delete crd probes.monitoring.coreos.com || true
            kubectl delete crd thanosrulers.monitoring.coreos.com || true
            print_success "CRDs deleted"
        else
            print_info "Skipping CRD deletion"
        fi
    else
        print_info "Skipping CRD deletion"
    fi
}

show_remaining_resources() {
    print_header "Checking Remaining Resources"

    if kubectl get namespace $NAMESPACE &> /dev/null; then
        echo "Remaining resources in namespace '$NAMESPACE':"
        echo ""
        echo "Pods:"
        kubectl get pods -n $NAMESPACE || echo "  None"
        echo ""
        echo "PVCs:"
        kubectl get pvc -n $NAMESPACE || echo "  None"
        echo ""
    else
        print_info "Namespace '$NAMESPACE' has been deleted"
    fi
}

# Main execution
main() {
    print_header "Monitoring Stack Uninstall"

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi

    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install helm first."
        exit 1
    fi

    confirm_uninstall
    uninstall_blackbox_exporter
    uninstall_loki_stack
    uninstall_prometheus_stack
    cleanup_pvcs
    cleanup_namespace
    cleanup_crds
    show_remaining_resources

    print_success "Uninstall complete!"
}

# Run main function
main
