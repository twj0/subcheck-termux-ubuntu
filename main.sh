#!/bin/bash

# SubsCheck Termux/Ubuntu Version
# Main script

# --- Configuration ---
# Path to the scripts directory
SCRIPT_DIR="$(dirname "$0")/scripts"

# Path to the xray core executable
XRAY_PATH="$(dirname "$0")/xray/xray"

# Temporary directory for configs and logs
TEMP_DIR="/tmp/subscheck"
mkdir -p "$TEMP_DIR"

# --- Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# --- Main Logic ---
log "Starting SubsCheck..."

# Check for input
if [ -z "$1" ]; then
    echo "Usage: $0 <subscription_url_or_file_path>"
    exit 1
fi

INPUT="$1"

# Parse nodes
log "Parsing nodes from $INPUT..."
# The parse.sh script should output a standardized format, e.g., one JSON object per line
NODES=$("$SCRIPT_DIR/parse.sh" "$INPUT")

if [ -z "$NODES" ]; then
    log "No nodes found. Exiting."
    exit 1
fi

log "Parsing complete. Starting tests..."
TOTAL_NODES=$(echo "$NODES" | wc -l)
CURRENT_NODE=0

# Loop through each node and test it
while IFS= read -r NODE_INFO; do
    CURRENT_NODE=$((CURRENT_NODE + 1))
    log "Testing node $CURRENT_NODE/$TOTAL_NODES..."
    
    # Pass the standardized node info and xray path to the test script
    RESULT=$("$SCRIPT_DIR/test_node.sh" "$NODE_INFO" "$XRAY_PATH" "$TEMP_DIR")
    
    # Output the result
    echo "$RESULT"
    
done <<< "$NODES"

log "All tests finished."

# Clean up
cleanup

exit 0