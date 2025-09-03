#!/bin/bash

# Enhanced main script with SubsCheck-Win-GUI insights
# Supports configuration file, better error handling, and multiple output formats

set -e

# Default configuration
CONCURRENT=10
TIMEOUT=5000
SPEEDTEST_TIMEOUT=10
MIN_SPEED=1
MAX_LATENCY=1000
OUTPUT_FORMAT="json"
OUTPUT_FILE="results.json"
SAVE_WORKING_NODES=true
RETRY_COUNT=2
RETRY_DELAY=1

# Load configuration if exists
if [ -f "config.yaml" ]; then
    echo "[INFO] Loading configuration from config.yaml"
    
    # Parse YAML config using yq if available
    if command -v yq > /dev/null 2>&1; then
        CONCURRENT=$(yq eval '.concurrent // 10' config.yaml)
        TIMEOUT=$(yq eval '.timeout // 5000' config.yaml)
        SPEEDTEST_TIMEOUT=$(yq eval '.speedtest-timeout // 10' config.yaml)
        MIN_SPEED=$(yq eval '.min-speed // 1' config.yaml)
        MAX_LATENCY=$(yq eval '.max-latency // 1000' config.yaml)
        OUTPUT_FORMAT=$(yq eval '.output-format // "json"' config.yaml)
        OUTPUT_FILE=$(yq eval '.output-file // "results.json"' config.yaml)
        SAVE_WORKING_NODES=$(yq eval '.save-working-nodes // true' config.yaml)
        RETRY_COUNT=$(yq eval '.retry-count // 2' config.yaml)
        RETRY_DELAY=$(yq eval '.retry-delay // 1' config.yaml)
    fi
fi

# Helper functions
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

show_help() {
    cat << EOF
Enhanced SubCheck - Node Testing Tool

Usage: $0 [OPTIONS] <subscription_url_or_file>

Options:
  -c, --concurrent NUM     Number of concurrent tests (default: $CONCURRENT)
  -t, --timeout MS         Timeout in milliseconds (default: $TIMEOUT)
  -s, --speedtest-timeout SEC  Speed test timeout in seconds (default: $SPEEDTEST_TIMEOUT)
  -m, --min-speed MBPS     Minimum speed requirement (default: $MIN_SPEED MB/s)
  -l, --max-latency MS     Maximum latency allowed (default: $MAX_LATENCY ms)
  -f, --format FORMAT      Output format: json, yaml, base64 (default: $OUTPUT_FORMAT)
  -o, --output FILE        Output file (default: $OUTPUT_FILE)
  -r, --retry NUM          Retry count for failed tests (default: $RETRY_COUNT)
  -d, --debug              Enable debug mode
  -h, --help               Show this help message

Examples:
  $0 subscription.txt
  $0 -c 20 -t 3000 -f yaml https://example.com/sub
  $0 --debug --min-speed 5 subscription.txt

Configuration:
  Create config.yaml to set default values for all options.
EOF
}

# Parse command line arguments
DEBUG=false
LIMIT=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--concurrent)
            CONCURRENT="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -s|--speedtest-timeout)
            SPEEDTEST_TIMEOUT="$2"
            shift 2
            ;;
        -m|--min-speed)
            MIN_SPEED="$2"
            shift 2
            ;;
        -l|--max-latency)
            MAX_LATENCY="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -r|--retry)
            RETRY_COUNT="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            SUBSCRIPTION_INPUT="$1"
            shift
            ;;
    esac
done

# Validate input
if [ -z "$SUBSCRIPTION_INPUT" ]; then
    print_error "No subscription URL or file provided"
    show_help
    exit 1
fi

# Check dependencies
for cmd in curl jq; do
    if ! command -v $cmd > /dev/null 2>&1; then
        print_error "Missing dependency: $cmd"
        exit 1
    fi
done

# Check if Xray core exists
if [ ! -f "xray" ]; then
    print_error "Xray core not found. Run init.sh first."
    exit 1
fi

print_info "=== Enhanced SubCheck Starting ==="
print_info "Configuration: concurrent=$CONCURRENT, timeout=${TIMEOUT}ms, format=$OUTPUT_FORMAT"

# Parse subscription
print_info "Parsing subscription..."
NODES_JSON=$(bash scripts/parse.sh "$SUBSCRIPTION_INPUT")

if [ -z "$NODES_JSON" ] || [ "$NODES_JSON" = "[]" ]; then
    print_error "No nodes found in subscription"
    exit 1
fi

NODE_COUNT=$(echo "$NODES_JSON" | jq 'length')
print_info "Found $NODE_COUNT nodes to test"

if [ $LIMIT -gt 0 ] && [ $LIMIT -lt $NODE_COUNT ]; then
    print_info "Limiting tests to first $LIMIT nodes"
    NODES_JSON=$(echo "$NODES_JSON" | jq ".[:$LIMIT]")
    NODE_COUNT=$LIMIT
fi

# Test nodes with enhanced logic
RESULTS="[]"
TESTED=0
WORKING=0
FAILED=0

print_info "Starting node tests..."

for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE=$(echo "$NODES_JSON" | jq ".[$i]")
    NODE_NAME=$(echo "$NODE" | jq -r '.name')
    
    TESTED=$((TESTED + 1))
    echo -n "[$TESTED/$NODE_COUNT] Testing: $NODE_NAME... "
    
    # Test with retry logic
    RESULT=""
    for attempt in $(seq 1 $RETRY_COUNT); do
        if [ $attempt -gt 1 ]; then
            [ "$DEBUG" = true ] && echo "[DEBUG] Retry attempt $attempt for $NODE_NAME"
            sleep $RETRY_DELAY
        fi
        
        RESULT=$(echo "$NODE" | timeout $((TIMEOUT / 1000 + 1)) bash scripts/test_node.sh 2>/dev/null || echo "")
        
        if [ ! -z "$RESULT" ]; then
            SUCCESS=$(echo "$RESULT" | jq -r '.success // false')
            if [ "$SUCCESS" = "true" ]; then
                # Check if node meets quality requirements
                LATENCY=$(echo "$RESULT" | jq -r '.latency // -1')
                DOWNLOAD=$(echo "$RESULT" | jq -r '.download // -1')
                
                MEETS_REQUIREMENTS=true
                if [ "$LATENCY" != "-1" ] && [ "$LATENCY" -gt "$MAX_LATENCY" ]; then
                    MEETS_REQUIREMENTS=false
                    [ "$DEBUG" = true ] && echo "[DEBUG] Node $NODE_NAME rejected: latency ${LATENCY}ms > ${MAX_LATENCY}ms"
                fi
                
                if [ "$DOWNLOAD" != "-1" ] && [ "$(echo "$DOWNLOAD < $MIN_SPEED" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
                    MEETS_REQUIREMENTS=false
                    [ "$DEBUG" = true ] && echo "[DEBUG] Node $NODE_NAME rejected: speed ${DOWNLOAD}MB/s < ${MIN_SPEED}MB/s"
                fi
                
                if [ "$MEETS_REQUIREMENTS" = true ] || [ "$SAVE_WORKING_NODES" = false ]; then
                    break
                fi
            fi
        fi
    done
    
    if [ ! -z "$RESULT" ]; then
        SUCCESS=$(echo "$RESULT" | jq -r '.success // false')
        if [ "$SUCCESS" = "true" ]; then
            WORKING=$((WORKING + 1))
            echo "✅"
        else
            FAILED=$((FAILED + 1))
            echo "❌"
        fi
        
        # Add result to collection (only working nodes if SAVE_WORKING_NODES is true)
        if [ "$SAVE_WORKING_NODES" = false ] || [ "$SUCCESS" = "true" ]; then
            RESULTS=$(echo "$RESULTS" | jq --argjson result "$RESULT" '. + [$result]')
        fi
    else
        FAILED=$((FAILED + 1))
        echo "❌ (timeout)"
    fi
done

print_info "=== Test Summary ==="
print_info "Total: $TESTED, Working: $WORKING, Failed: $FAILED"

# Output results in requested format
case "$OUTPUT_FORMAT" in
    "json")
        echo "$RESULTS" > "$OUTPUT_FILE"
        print_info "Results saved to $OUTPUT_FILE (JSON format)"
        ;;
    "yaml")
        if command -v yq > /dev/null 2>&1; then
            echo "$RESULTS" | yq eval -P '.' > "${OUTPUT_FILE%.json}.yaml"
            print_info "Results saved to ${OUTPUT_FILE%.json}.yaml (YAML format)"
        else
            print_warning "yq not found, saving as JSON instead"
            echo "$RESULTS" > "$OUTPUT_FILE"
        fi
        ;;
    "base64")
        # Convert working nodes back to base64 format for v2rayN compatibility
        BASE64_OUTPUT=""
        WORKING_COUNT=$(echo "$RESULTS" | jq 'length')
        for i in $(seq 0 $((WORKING_COUNT - 1))); do
            NODE=$(echo "$RESULTS" | jq ".[$i]")
            # This would need protocol-specific reconstruction logic
            # For now, just save as JSON with a note
            print_warning "Base64 output format not fully implemented yet"
        done
        echo "$RESULTS" > "$OUTPUT_FILE"
        ;;
    *)
        print_error "Unknown output format: $OUTPUT_FORMAT"
        echo "$RESULTS" > "$OUTPUT_FILE"
        ;;
esac

if [ $WORKING -gt 0 ]; then
    print_info "✅ Found $WORKING working nodes"
    exit 0
else
    print_error "❌ No working nodes found"
    exit 1
fi
