#!/bin/bash

# mobile_check.sh - A robust node checker for Termux
# Combines the power of parse.sh and test_node.sh

# --- Style and Formatting ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# --- Main Logic ---
main() {
    local subscription_file="$1"

    if [ -z "$subscription_file" ]; then
        print_error "Usage: $0 <subscription_file>"
        print_error "Example: $0 subscription.txt"
        exit 1
    fi

    if [ ! -f "$subscription_file" ]; then
        print_error "Subscription file not found: '$subscription_file'"
        exit 1
    fi

    print_info "Starting node check for '$subscription_file'..."

    # 1. Parse the subscription file to get a JSON array of nodes
    # We redirect stderr to /dev/null to hide the progress messages from parse.sh
    local nodes_json
    nodes_json=$(bash scripts/parse.sh "$subscription_file" 2>/dev/null)

    if [ -z "$nodes_json" ] || [ "$nodes_json" == "[]" ]; then
        print_error "No nodes found or failed to parse. Please check the subscription file."
        exit 1
    fi

    local total_nodes
    total_nodes=$(echo "$nodes_json" | jq 'length')
    print_info "Found $total_nodes nodes. Starting tests..."
    echo "-----------------------------------------------------"

    # 2. Loop through each node and test it
    local working_count=0
    local results=""
    for i in $(seq 0 $((total_nodes - 1))); do
        local node_json
        node_json=$(echo "$nodes_json" | jq -c ".[$i]")
        
        local node_name
        node_name=$(echo "$node_json" | jq -r '.name')

        echo -n "[$((i + 1))/$total_nodes] Testing node: ${node_name}..."

        # Call the test script for the single node
        local result_json
        result_json=$(bash scripts/test_node.sh "$node_json")
        
        local success
        success=$(echo "$result_json" | jq -r '.success')

        if [ "$success" == "true" ]; then
            local latency
            latency=$(echo "$result_json" | jq -r '.latency')
            working_count=$((working_count + 1))
            echo -e " ${GREEN}✅ Success!${NC} Latency: ${latency}ms"
            results+="${GREEN}[Success]${NC} ${node_name} - Latency: ${latency}ms\n"
        else
            local error_msg
            error_msg=$(echo "$result_json" | jq -r '.error')
            echo -e " ${RED}❌ Failed.${NC} Reason: ${error_msg}"
            results+="${RED}[Failed]${NC}  ${node_name} - Error: ${error_msg}\n"
        fi
    done

    # 3. Print summary
    echo "-----------------------------------------------------"
    print_info "Test finished."
    print_info "Summary: ${working_count} out of ${total_nodes} nodes are working."
    echo -e "\n--- Detailed Results ---\n"
    echo -e "$results"
}

# Run main function
main "$@"