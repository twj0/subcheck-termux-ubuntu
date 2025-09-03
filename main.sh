#!/bin/bash

# Exit on error
set -e

# --- Helper Functions ---
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# --- Script Usage ---
usage() {
    echo "Usage: $0 -i <input_url_or_file> [-o <output_file.json>] [-d] [-l <limit>]"
    echo "  -i: Subscription URL or local file path (e.g., config.yaml)"
    echo "  -o: (Optional) Path to save the output JSON file."
    echo "  -d: (Optional) Enable debug mode for verbose output."
    echo "  -l: (Optional) Limit the number of nodes to test (default: all)."
    exit 1
}

# --- Main Logic ---

INPUT_SOURCE=""
OUTPUT_FILE=""
DEBUG_MODE=false
NODE_LIMIT=""

# Parse command-line arguments
while getopts ":i:o:dl:" opt; do
  case ${opt} in
    i )
      INPUT_SOURCE=$OPTARG
      ;;
    o )
      OUTPUT_FILE=$OPTARG
      ;;
    d )
      DEBUG_MODE=true
      ;;
    l )
      NODE_LIMIT=$OPTARG
      ;;
    \? )
      usage
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      usage
      ;;
  esac
done

# Check if input is provided
if [ -z "$INPUT_SOURCE" ]; then
    print_error "Input source is mandatory."
    usage
fi

# --- Main Test Function ---
# This function tests a single subscription source (URL or file)
test_subscription() {
    local sub_source=$1
    local all_results="[]"

    print_info "Parsing nodes from '$sub_source'..."
    # The parse script outputs a JSON array, or JSON objects on new lines for YAML
    local nodes_json
    nodes_json=$(scripts/parse.sh "$sub_source")

    if [ -z "$nodes_json" ] || ! echo "$nodes_json" | jq . > /dev/null 2>&1; then
        print_error "Failed to parse nodes from '$sub_source' or parsing returned empty/invalid JSON."
        return
    fi

    local node_count
    node_count=$(echo "$nodes_json" | jq 'length')
    print_info "Found $node_count nodes to test from '$sub_source'."

    # Apply node limit if specified
    local test_count=$node_count
    if [ ! -z "$NODE_LIMIT" ] && [ "$NODE_LIMIT" -lt "$node_count" ]; then
        test_count=$NODE_LIMIT
        print_info "Limiting test to first $test_count nodes."
    fi

    for i in $(seq 0 $(($test_count - 1))); do
        local node_json
        node_json=$(echo "$nodes_json" | jq -c ".[$i]")
        local node_name
        node_name=$(echo "$node_json" | jq -r '.name')
        
        print_info "Testing node $((i+1))/$test_count: $node_name"
        
        if [ "$DEBUG_MODE" = true ]; then
            echo "[DEBUG] Node JSON: $node_json"
        fi
        
        local result
        result=$( (scripts/test_node.sh "$node_json") || echo "{\"name\":\"$node_name\",\"success\":false,\"error\":\"Test script failed unexpectedly.\"}" )
        
        # Add the result to our list of all results
        all_results=$(echo "$all_results" | jq --argjson res "$result" '. + [$res]')
        
        echo "$result" | jq '.'
    done
    echo "$all_results"
}


# --- Script Body ---

# Check if the input is a file containing a list of URLs
IS_URL_LIST=false
if [ -f "$INPUT_SOURCE" ]; then
    # Check if the first line looks like a URL
    FIRST_LINE=$(head -n 1 "$INPUT_SOURCE")
    if [[ "$FIRST_LINE" == http* ]]; then
        IS_URL_LIST=true
    fi
fi

ALL_RESULTS="[]"

if [ "$IS_URL_LIST" = true ]; then
    print_info "Input file detected as a list of subscription URLs. Testing each one..."
    while IFS= read -r sub_url; do
        [ -z "$sub_url" ] && continue
        SUB_RESULTS=$(test_subscription "$sub_url")
        # Merge results from this subscription into the main list, only if SUB_RESULTS is not empty
        if [ -n "$SUB_RESULTS" ] && echo "$SUB_RESULTS" | jq . > /dev/null 2>&1; then
            ALL_RESULTS=$(echo "$ALL_RESULTS" | jq --argjson sub "$SUB_RESULTS" '. + $sub')
        fi
    done < "$INPUT_SOURCE"
else
    # It's a single subscription source
    ALL_RESULTS=$(test_subscription "$INPUT_SOURCE")
fi

# 3. Output final results
print_info "All tests complete."

if [ -z "$OUTPUT_FILE" ]; then
    print_info "Final results:"
    echo "$ALL_RESULTS" | jq '.'
else
    print_info "Saving results to '$OUTPUT_FILE'..."
    echo "$ALL_RESULTS" | jq '.' > "$OUTPUT_FILE"
    print_info "Done."
fi

exit 0