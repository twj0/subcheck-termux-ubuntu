#!/bin/bash

# Simple test that bypasses Xray entirely - just tests basic parsing and connectivity

set -e

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# Test subscription parsing only
test_parsing_only() {
    local url="$1"
    
    print_info "Testing subscription parsing: $url"
    
    # Test parsing with timeout and show errors
    local nodes_json
    local parse_stderr
    print_info "Running: bash scripts/parse.sh \"$url\""
    
    # Capture both stdout and stderr separately
    {
        nodes_json=$(timeout 3 bash scripts/parse.sh "$url" 2>&3)
    } 3>&2 2>&1 | {
        parse_stderr=$(cat)
    }
    
    # Show stderr output for debugging
    if [ ! -z "$parse_stderr" ]; then
        echo "[DEBUG] Parse script stderr: $parse_stderr"
    fi
    
    # If parsing failed, set empty array
    if [ -z "$nodes_json" ]; then
        nodes_json="[]"
    fi
    
    if [ "$nodes_json" = "[]" ] || [ -z "$nodes_json" ]; then
        print_error "Parsing failed or no nodes found"
        return 1
    fi
    
    local node_count
    # Debug: show first few lines of JSON to understand format
    echo "[DEBUG] First 3 lines of JSON output:"
    echo "$nodes_json" | head -3
    
    node_count=$(echo "$nodes_json" | jq 'length' 2>/dev/null || echo "0")
    echo "[DEBUG] Node count: $node_count"
    
    if [ "$node_count" -gt 0 ]; then
        print_info "✅ Successfully parsed $node_count nodes"
        
        # Show first 3 nodes
        for i in $(seq 0 2); do
            if [ $i -ge $node_count ]; then
                break
            fi
            
            local node_name
            local node_address
            local node_port
            
            node_name=$(echo "$nodes_json" | jq -r ".[$i].name" 2>/dev/null || echo "Unknown")
            node_address=$(echo "$nodes_json" | jq -r ".[$i].address" 2>/dev/null || echo "Unknown")
            node_port=$(echo "$nodes_json" | jq -r ".[$i].port" 2>/dev/null || echo "Unknown")
            
            echo "  $((i+1)). $node_name ($node_address:$node_port)"
        done
        return 0
    else
        print_error "No valid nodes found"
        return 1
    fi
}

# Main execution
print_info "=== Simple Parsing Test (No Proxy Testing) ==="

# Check dependencies
for cmd in curl jq; do
    if ! command -v $cmd > /dev/null 2>&1; then
        print_error "Missing dependency: $cmd"
        exit 1
    fi
done

# Get subscription URL
if [ ! -f "subscription.txt" ]; then
    print_error "subscription.txt not found!"
    exit 1
fi

FIRST_URL=$(head -n 1 subscription.txt | tr -d '\r\n')

if [ -z "$FIRST_URL" ]; then
    print_error "No URL found in subscription.txt"
    exit 1
fi

# Test parsing
if test_parsing_only "$FIRST_URL"; then
    print_info "=== Parsing test completed successfully ==="
    print_info "To test actual proxy connections, run: bash run.sh"
else
    print_error "=== Parsing test failed ==="
    exit 1
fi
