#!/bin/bash

# Quick test script for subcheck project
# Tests a single subscription URL with limited nodes

set -e

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# Check if required tools are available
check_dependencies() {
    local missing_deps=""
    
    for cmd in curl jq; do
        if ! command -v $cmd > /dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done
    
    if [ ! -z "$missing_deps" ]; then
        print_error "Missing dependencies:$missing_deps"
        print_info "Please run: sudo apt install$missing_deps"
        exit 1
    fi
}

# Test a single subscription URL
test_single_subscription() {
    local url="$1"
    local limit="${2:-3}"
    
    print_info "Quick test: Testing first $limit nodes from subscription"
    print_info "URL: $url"
    
    # Run main script with debug mode and limit
    bash main.sh -i "$url" -d -l "$limit"
}

# Main execution
print_info "Starting quick test..."

check_dependencies

# Use first URL from subscription.txt if available
if [ -f "subscription.txt" ]; then
    FIRST_URL=$(head -n 1 subscription.txt)
    if [ ! -z "$FIRST_URL" ]; then
        test_single_subscription "$FIRST_URL" 2
    else
        print_error "subscription.txt is empty"
        exit 1
    fi
else
    print_error "subscription.txt not found"
    print_info "Usage: $0"
    print_info "Make sure subscription.txt exists with at least one subscription URL"
    exit 1
fi

print_info "Quick test completed!"
