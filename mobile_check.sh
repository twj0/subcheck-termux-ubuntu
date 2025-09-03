#!/bin/bash

# mobile_check.sh - A self-contained, robust node checker for Termux
# Inspired by the integrated logic of subcheck-win-gui and simple_china_test.sh

# --- Configuration & Style ---
XRAY_BIN="./xray/xray"
CURL_TIMEOUT=10
TEST_URL="http://www.google.com/gen_204"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Helper Functions ---
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# --- Module 1: Fetch Subscription ---
fetch_subscription() {
    local url="$1"
    local effective_url="$url"

    if [[ "$url" == *"github.com"* ]] || [[ "$url" == *"githubusercontent.com"* ]]; then
        print_info "GitHub URL detected. Using proxy."
        effective_url="https://ghfast.top/${url}"
    fi

    print_info "Fetching subscription from: $effective_url"
    local content
    content=$(curl -sL --connect-timeout $CURL_TIMEOUT --max-time 30 "$effective_url")

    if [ -z "$content" ]; then
        print_error "Failed to download subscription. The URL might be invalid or network is down."
        return 1
    fi
    echo "$content"
}

# --- Module 2: Decode Content ---
decode_content() {
    local content="$1"
    # A simple heuristic to check if the content is likely base64
    if ! echo "$content" | grep -q "://"; then
        print_info "Base64 encoding detected, decoding..."
        local decoded_content
        decoded_content=$(echo "$content" | base64 -d 2>/dev/null)
        if [ $? -ne 0 ]; then
            print_error "Base64 decoding failed. The content might be corrupted."
            return 1
        fi
        echo "$decoded_content"
    else
        echo "$content"
    fi
}

# --- Module 3: Parse Nodes ---
parse_nodes() {
    local content="$1"
    local nodes_json="[]"
    
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r\n')
        [ -z "$line" ] && continue

        local node_json=""
        if [[ "$line" == vless://* ]]; then
            local stripped="${line#vless://}"
            local user_info=$(echo "$stripped" | cut -d'@' -f1)
            local host_info=$(echo "$stripped" | cut -d'@' -f2)
            local addr_port=$(echo "$host_info" | cut -d'?' -f1)
            local address=$(echo "$addr_port" | cut -d':' -f1)
            local port=$(echo "$addr_port" | cut -d':' -f2)
            local params=$(echo "$host_info" | cut -d'?' -f2)
            local name=$(echo "$params" | cut -d'#' -f2 | sed 's/%20/ /g')
            [ -z "$name" ] && name="$address:$port"
            
            node_json=$(jq -n \
                --arg protocol "vless" --arg name "$name" \
                --arg address "$address" --arg port "$port" \
                --arg id "$user_info" '{protocol:$protocol, name:$name, address:$address, port:$port, id:$id}')

        elif [[ "$line" == vmess://* ]]; then
            local base64_part="${line#vmess://}"
            local decoded
            if decoded=$(echo "$base64_part" | base64 -d 2>/dev/null); then
                local name=$(echo "$decoded" | jq -r '.ps // "Unknown"')
                local address=$(echo "$decoded" | jq -r '.add // ""')
                local port=$(echo "$decoded" | jq -r '.port // ""')
                local id=$(echo "$decoded" | jq -r '.id // ""')
                
                if [ -n "$address" ] && [ -n "$port" ]; then
                     node_json=$(jq -n \
                        --arg protocol "vmess" --arg name "$name" \
                        --arg address "$address" --arg port "$port" \
                        --arg id "$id" '{protocol:$protocol, name:$name, address:$address, port:$port, id:$id}')
                fi
            fi
        fi

        if [ -n "$node_json" ]; then
            nodes_json=$(echo "$nodes_json" | jq --argjson node "$node_json" '. + [$node]')
        fi
    done <<< "$content"
    
    echo "$nodes_json"
}

# --- Module 4: Test Single Node (Integrated from test_node.sh) ---
test_single_node() {
    local node_json="$1"
    local temp_config="temp_config_$$.json"
    local socks_port=10808
    local xray_pid=""

    # Cleanup function for this test
    cleanup() {
        if [ -n "$xray_pid" ] && ps -p "$xray_pid" > /dev/null; then
            kill "$xray_pid"
        fi
        rm -f "$temp_config"
    }
    trap cleanup RETURN

    # Generate xray config
    local protocol=$(echo "$node_json" | jq -r '.protocol')
    local address=$(echo "$node_json" | jq -r '.address')
    local port=$(echo "$node_json" | jq -r '.port')
    local id=$(echo "$node_json" | jq -r '.id')

    # Simplified config generator
    jq -n \
    --arg address "$address" --argport "$port" --arg id "$id" \
    '{
        "inbounds": [{"port": '$socks_port', "protocol": "socks", "settings": {"auth": "noauth"}}],
        "outbounds": [{
            "protocol": "'$protocol'",
            "settings": { "vnext": [{ "address": $address, "port": '$port', "users": [{"id": $id}] }] }
        }]
    }' > "$temp_config"

    # Start xray
    "$XRAY_BIN" -c "$temp_config" > /dev/null 2>&1 &
    xray_pid=$!
    sleep 1.5 # Give xray time to start

    if ! ps -p "$xray_pid" > /dev/null; then
        echo '{"success":false, "error":"Failed to start Xray core."}'
        return
    fi

    # Test Latency
    local latency_result
    latency_result=$(curl -s -o /dev/null --socks5-hostname "localhost:$socks_port" -w "%{time_connect}" --connect-timeout $CURL_TIMEOUT "$TEST_URL")
    
    if [ -z "$latency_result" ] || [[ "$latency_result" == "0.000" ]]; then
        echo '{"success":false, "error":"Latency test failed (timeout)."}'
        return
    fi

    local latency_ms
    latency_ms=$(awk "BEGIN {printf \"%.0f\", $latency_result * 1000}")
    echo "{\"success\":true, \"latency\":$latency_ms}"
}


# --- Module 5: Main Controller ---
main() {
    local subscription_file="$1"
    if [ -z "$subscription_file" ]; then
        print_error "Usage: $0 <subscription_file>"
        exit 1
    fi
    if [ ! -f "$subscription_file" ]; then
        print_error "File not found: '$subscription_file'"
        exit 1
    fi
    if [ ! -f "$XRAY_BIN" ]; then
        print_error "Xray binary not found at '$XRAY_BIN'. Please run init.sh."
        exit 1
    fi

    print_info "=== Starting SubCheck Mobile v2.0 ==="
    
    # 1. Get URL from file
    local sub_url
    sub_url=$(head -n 1 "$subscription_file" | tr -d '\r\n')
    if [[ ! "$sub_url" == http* ]]; then
        print_error "No valid URL found in '$subscription_file'."
        exit 1
    fi

    # 2. Fetch and Decode
    local raw_content
    raw_content=$(fetch_subscription "$sub_url")
    [ $? -ne 0 ] && exit 1
    
    local decoded_content
    decoded_content=$(decode_content "$raw_content")
    [ $? -ne 0 ] && exit 1

    # 3. Parse
    local nodes_json
    nodes_json=$(parse_nodes "$decoded_content")
    local total_nodes
    total_nodes=$(echo "$nodes_json" | jq 'length')

    if [ "$total_nodes" -eq 0 ]; then
        print_error "No nodes were parsed from the subscription."
        exit 1
    fi
    print_info "Parsed $total_nodes nodes. Starting tests..."
    echo "-----------------------------------------------------"

    # 4. Test and Summarize
    local working_count=0
    local results_summary=""
    for i in $(seq 0 $((total_nodes - 1))); do
        local node_json
        node_json=$(echo "$nodes_json" | jq -c ".[$i]")
        local node_name
        node_name=$(echo "$node_json" | jq -r '.name')

        echo -n "[$((i + 1))/$total_nodes] Testing: ${node_name}..."
        
        local result_json
        result_json=$(test_single_node "$node_json")
        
        if [[ "$(echo "$result_json" | jq -r '.success')" == "true" ]]; then
            local latency
            latency=$(echo "$result_json" | jq -r '.latency')
            working_count=$((working_count + 1))
            echo -e " ${GREEN}✅ Success!${NC} Latency: ${latency}ms"
            results_summary+="${GREEN}[Success]${NC} ${node_name} | Latency: ${latency}ms\n"
        else
            local error_msg
            error_msg=$(echo "$result_json" | jq -r '.error')
            echo -e " ${RED}❌ Failed.${NC} (${error_msg})"
            results_summary+="${RED}[Failed]${NC}  ${node_name} | ${error_msg}\n"
        fi
    done

    # 5. Final Report
    echo "-----------------------------------------------------"
    print_info "Test finished. ${working_count}/${total_nodes} nodes are working."
    echo -e "\n--- Detailed Results ---\n"
    echo -e "$results_summary"
}

main "$@"