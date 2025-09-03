#!/bin/bash

# SubsCheck Termux/Ubuntu Version
# Node parsing script

# --- Input ---
# $1: Subscription URL or local file path

INPUT="$1"

# --- Functions ---
# Function to decode base64 content
decode_base64() {
    echo "$1" | base64 --decode
}

# Function to parse vless/vmess links (basic example)
parse_uri() {
    # This is a simplified parser. A more robust solution might use jq or other tools.
    PROTOCOL=$(echo "$1" | cut -d: -f1)
    ENCODED_PART=$(echo "$1" | sed -e "s/^$PROTOCOL:\/\///")
    
    # Further parsing is needed here to extract server, port, uuid, etc.
    # For now, we just return the link as a placeholder.
    # A real implementation would convert this to a standard JSON format.
    echo "{\"protocol\": \"$PROTOCOL\", \"link\": \"$1\"}"
}

# --- Main Logic ---
if [[ "$INPUT" =~ ^https?:// ]]; then
    # It's a URL
    CONTENT=$(curl -s -L "$INPUT")
    
    # Check if it's a base64 encoded subscription
    # A simple heuristic: check if decoding produces valid-looking text
    DECODED_CONTENT=$(decode_base64 "$CONTENT")
    if [[ "$DECODED_CONTENT" =~ vless:// || "$DECODED_CONTENT" =~ vmess:// ]]; then
        echo "$DECODED_CONTENT" | while IFS= read -r line; do
            parse_uri "$line"
        done
    else
        # Assume it's a Clash YAML file
        # Use yq to extract proxy information
        # This example extracts name and server, a real one would get all details
        echo "$CONTENT" | yq e '.proxies[] | {"name": .name, "server": .server, "port": .port, "type": .type, "uuid": .uuid, "alterId": .alterId, "cipher": .cipher, "tls": .tls, "network": .network}' -o=json | jq -c .
    fi
else
    # It's a local file
    if [ -f "$INPUT" ]; then
        # Assume it's a Clash YAML file
        cat "$INPUT" | yq e '.proxies[] | {"name": .name, "server": .server, "port": .port, "type": .type, "uuid": .uuid, "alterId": .alterId, "cipher": .cipher, "tls": .tls, "network": .network}' -o=json | jq -c .
    else
        echo "Error: File not found at $INPUT" >&2
        exit 1
    fi
fi