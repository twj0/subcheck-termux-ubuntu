#!/bin/bash

# Ultra-fast connectivity test - only check if proxy works
# No speed test, just basic connectivity

set -e

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# Test a single node with minimal overhead
test_node_connectivity() {
    local node_json="$1"
    local node_name=$(echo "$node_json" | jq -r '.name')
    
    print_info "Testing: $node_name"
    
    # Quick connectivity test without Xray - just check if we can parse the node
    local address=$(echo "$node_json" | jq -r '.address')
    local port=$(echo "$node_json" | jq -r '.port')
    
    # Simple TCP connectivity test
    if timeout 2 bash -c "echo >/dev/tcp/$address/$port" 2>/dev/null; then
        echo "✅ $node_name - TCP connection OK ($address:$port)"
        return 0
    else
        echo "❌ $node_name - TCP connection failed ($address:$port)"
        return 1
    fi
}

# Main execution
print_info "=== Ultra-Fast Connectivity Test ==="

# Get first URL from subscription
if [ ! -f "subscription.txt" ]; then
    print_error "subscription.txt not found!"
    exit 1
fi

FIRST_URL=$(head -n 1 subscription.txt | tr -d '\r\n')
print_info "Testing nodes from: $FIRST_URL"

# Parse nodes
print_info "Parsing subscription..."
NODES_JSON=$(bash scripts/parse.sh "$FIRST_URL" 2>/dev/null)

if [ -z "$NODES_JSON" ]; then
    print_error "No nodes found"
    exit 1
fi

NODE_COUNT=$(echo "$NODES_JSON" | jq 'length')
print_info "Found $NODE_COUNT nodes, testing first 3..."

# Test first 3 nodes
WORKING_COUNT=0
for i in $(seq 0 2); do
    if [ $i -ge $NODE_COUNT ]; then
        break
    fi
    
    NODE_JSON=$(echo "$NODES_JSON" | jq -c ".[$i]")
    if test_node_connectivity "$NODE_JSON"; then
        WORKING_COUNT=$((WORKING_COUNT + 1))
    fi
done

print_info "=== Results: $WORKING_COUNT/3 nodes have TCP connectivity ==="
