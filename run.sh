#!/bin/bash

# One-click run script for subcheck
# Automatically handles permissions and runs quick test

set -e

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

# Function to test if script has execute permission
test_executable() {
    local script="$1"
    if [ -x "$script" ]; then
        return 0
    else
        return 1
    fi
}

# Function to make scripts executable if needed
ensure_executable() {
    local scripts=("main.sh" "scripts/parse.sh" "scripts/test_node.sh" "init.sh" "quick_test.sh")
    local need_chmod=false
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ] && ! test_executable "$script"; then
            need_chmod=true
            break
        fi
    done
    
    if [ "$need_chmod" = true ]; then
        print_info "Setting execute permissions for scripts..."
        chmod +x "${scripts[@]}" 2>/dev/null || {
            print_warning "Could not set permissions automatically. You may need to run:"
            print_warning "chmod +x *.sh scripts/*.sh"
        }
    fi
}

# Function to test a single URL with timeout
test_single_url() {
    local url="$1"
    local timeout_duration=60
    
    print_info "Testing subscription: $url"
    print_info "Timeout: ${timeout_duration}s"
    
    # Run with timeout to prevent hanging
    timeout $timeout_duration bash main.sh -i "$url" -l 2 -d 2>/dev/null || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            print_error "Test timed out after ${timeout_duration} seconds"
            print_info "This might be due to network issues or slow subscription server"
        else
            print_error "Test failed with exit code: $exit_code"
        fi
        return $exit_code
    }
}

# Main execution
print_info "=== SubCheck One-Click Runner ==="

# Ensure scripts are executable
ensure_executable

# Check if subscription file exists
if [ ! -f "subscription.txt" ]; then
    print_error "subscription.txt not found!"
    print_info "Creating a sample subscription.txt with a test URL..."
    echo "https://raw.githubusercontent.com/mfuu/v2ray/master/v2ray" > subscription.txt
    print_info "Created subscription.txt with sample URL"
fi

# Get first URL from subscription file
FIRST_URL=$(head -n 1 subscription.txt | tr -d '\r\n')
if [ -z "$FIRST_URL" ]; then
    print_error "No URLs found in subscription.txt"
    exit 1
fi

print_info "Found URL: $FIRST_URL"

# Test the URL
test_single_url "$FIRST_URL"

print_info "=== Test completed ==="
print_info "For more options, use: bash main.sh -h"
