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
    echo "Usage: $0 -i <input_url_or_file> [-o <output_file.json>]"
    echo "  -i: Subscription URL or local file path (e.g., config.yaml)"
    echo "  -o: (Optional) Path to save the output JSON file."
    exit 1
}

# --- Main Logic ---

INPUT_SOURCE=""
OUTPUT_FILE=""

# Parse command-line arguments
while getopts ":i:o:" opt; do
  case ${opt} in
    i )
      INPUT_SOURCE=$OPTARG
      ;;
    o )
      OUTPUT_FILE=$OPTARG
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

# 1. Parse nodes
print_info "Parsing nodes from '$INPUT_SOURCE'..."
# The parse script outputs a JSON array, or JSON objects on new lines for YAML
NODES_JSON=$(scripts/parse.sh "$INPUT_SOURCE")

if [ -z "$NODES_JSON" ] || ! echo "$NODES_JSON" | jq . > /dev/null 2>&1; then
    print_error "Failed to parse nodes or parsing returned empty/invalid JSON."
    exit 1
fi

# Get the number of nodes
NODE_COUNT=$(echo "$NODES_JSON" | jq 'length')
print_info "Found $NODE_COUNT nodes to test."

# 2. Loop through nodes and test them
ALL_RESULTS="[]"
for i in $(seq 0 $(($NODE_COUNT - 1))); do
    NODE_JSON=$(echo "$NODES_JSON" | jq -c ".[$i]")
    NODE_NAME=$(echo "$NODE_JSON" | jq -r '.name')
    
    print_info "Testing node $((i+1))/$NODE_COUNT: $NODE_NAME"
    
    # Run the test script for the current node
    # Use a subshell to capture output and handle potential errors
    RESULT=$( (scripts/test_node.sh "$NODE_JSON") || echo "{\"name\":\"$NODE_NAME\",\"success\":false,\"error\":\"Test script failed unexpectedly.\"}" )
    
    # Add the result to our list of all results
    ALL_RESULTS=$(echo "$ALL_RESULTS" | jq --argjson res "$RESULT" '. + [$res]')
    
    # Optional: Print intermediate result
    echo "$RESULT" | jq '.'
done

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