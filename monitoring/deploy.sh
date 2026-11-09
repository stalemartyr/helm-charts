#!/bin/bash

# Monitoring Stack Deployment Script
# Deploys Prometheus, Grafana, Loki, and Promtail to Kubernetes

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

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    print_success "kubectl found"

    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install helm first."
        exit 1
    fi
    print_success "helm found"

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    print_success "Connected to Kubernetes cluster"
}

add_helm_repos() {
    print_header "Adding Helm Repositories"

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    print_success "Helm repositories added and updated"
}

create_namespace() {
    print_header "Creating Namespace"

    if kubectl get namespace $NAMESPACE &> /dev/null; then
        print_info "Namespace '$NAMESPACE' already exists"
    else
        kubectl create namespace $NAMESPACE
        print_success "Namespace '$NAMESPACE' created"
    fi
}

deploy_prometheus_stack() {
    print_header "Deploying Prometheus Stack"

    if helm list -n $NAMESPACE | grep -q $PROMETHEUS_RELEASE; then
        print_info "Prometheus stack already installed. Upgrading..."
        helm upgrade $PROMETHEUS_RELEASE prometheus-community/kube-prometheus-stack \
            --namespace $NAMESPACE \
            -f kube-prometheus-stack-values.yaml \
            --wait
        print_success "Prometheus stack upgraded"
    else
        print_info "Installing Prometheus stack..."
        helm install $PROMETHEUS_RELEASE prometheus-community/kube-prometheus-stack \
            --namespace $NAMESPACE \
            -f kube-prometheus-stack-values.yaml \
            --wait
        print_success "Prometheus stack installed"
    fi
}

deploy_loki_stack() {
    print_header "Deploying Loki Stack"

    if helm list -n $NAMESPACE | grep -q $LOKI_RELEASE; then
        print_info "Loki stack already installed. Upgrading..."
        helm upgrade $LOKI_RELEASE grafana/loki-stack \
            --namespace $NAMESPACE \
            -f loki-stack-values.yaml \
            --wait
        print_success "Loki stack upgraded"
    else
        print_info "Installing Loki stack..."
        helm install $LOKI_RELEASE grafana/loki-stack \
            --namespace $NAMESPACE \
            -f loki-stack-values.yaml \
            --wait
        print_success "Loki stack installed"
    fi
}

deploy_blackbox_exporter() {
    print_header "Deploying Blackbox Exporter"

    if helm list -n $NAMESPACE | grep -q $BLACKBOX_RELEASE; then
        print_info "Blackbox Exporter already installed. Upgrading..."
        helm upgrade $BLACKBOX_RELEASE prometheus-community/prometheus-blackbox-exporter \
            --namespace $NAMESPACE \
            -f blackbox-exporter-values.yaml \
            --wait
        print_success "Blackbox Exporter upgraded"
    else
        print_info "Installing Blackbox Exporter..."
        helm install $BLACKBOX_RELEASE prometheus-community/prometheus-blackbox-exporter \
            --namespace $NAMESPACE \
            -f blackbox-exporter-values.yaml \
            --wait
        print_success "Blackbox Exporter installed"
    fi
}

wait_for_pods() {
    print_header "Waiting for Pods to be Ready"

    print_info "Waiting for all pods in namespace '$NAMESPACE' to be ready..."
    kubectl wait --for=condition=ready pod \
        --all \
        --namespace=$NAMESPACE \
        --timeout=300s || true

    print_success "Pod status check complete"
}

display_access_info() {
    print_header "Access Information"

    echo ""
    echo "Grafana:"
    echo "  Username: admin"
    echo "  Password: St4l3M4rtyr1992"
    echo "  Port Forward: kubectl port-forward -n $NAMESPACE svc/$PROMETHEUS_RELEASE-grafana 3000:80"
    echo "  URL: http://localhost:3000"
    echo ""

    echo "Prometheus:"
    echo "  Port Forward: kubectl port-forward -n $NAMESPACE svc/$PROMETHEUS_RELEASE-kube-prom-prometheus 9090:9090"
    echo "  URL: http://localhost:9090"
    echo ""

    echo "Alertmanager:"
    echo "  Port Forward: kubectl port-forward -n $NAMESPACE svc/$PROMETHEUS_RELEASE-kube-prom-alertmanager 9093:9093"
    echo "  URL: http://localhost:9093"
    echo ""

    echo "Loki:"
    echo "  Port Forward: kubectl port-forward -n $NAMESPACE svc/$LOKI_RELEASE 3100:3100"
    echo "  URL: http://localhost:3100"
    echo ""

    echo "Check pod status:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo ""
}

show_pod_status() {
    print_header "Pod Status"
    kubectl get pods -n $NAMESPACE
    echo ""
}

# Main execution
main() {
    print_header "Monitoring Stack Deployment"

    check_prerequisites
    add_helm_repos
    create_namespace
    deploy_prometheus_stack
    deploy_loki_stack
    deploy_blackbox_exporter
    wait_for_pods
    show_pod_status
    display_access_info

    print_success "Deployment complete!"
}

# Run main function
main
