#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

check_result() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$2"
        return 1
    fi
}

wait_for_constraint() {
    local constraint_name=$1
    print_info "Esperando que la constraint '$constraint_name' esté lista..."
    sleep 3
    if kubectl get constraint $constraint_name &>/dev/null; then
        print_success "✓ Constraint '$constraint_name' está activa"
    else
        print_warning "⚠ Constraint puede no estar completamente sincronizada"
    fi
}
