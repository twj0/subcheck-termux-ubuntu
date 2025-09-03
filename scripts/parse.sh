#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---
print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# Function to URL-decode strings
# Needed for node names (#...)
url_decode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# --- Parsers ---

# Parse a single vless:// link and convert to JSON
parse_vless_link() {
    local link=$1
    # Remove "vless://" prefix
    local stripped_link=${link#vless://}
    
    # Extract user info (UUID) and host info
    local user_info=$(echo "$stripped_link" | cut -d'@' -f1)
    local host_info=$(echo "$stripped_link" | cut -d'@' -f2)
    
    # Extract server address and port
    local server_address=$(echo "$host_info" | cut -d'?' -f1 | cut -d':' -f1)
    local server_port=$(echo "$host_info" | cut -d'?' -f1 | cut -d':' -f2)
    
    # Extract parameters
    local params=$(echo "$host_info" | cut -d'?' -f2)
    
    # Extract node name from the fragment (#)
    local node_name_encoded=$(echo "$params" | cut -d'#' -f2)
    local node_name=$(url_decode "$node_name_encoded")
    
    # Use jq to safely construct a JSON object
    jq -n \
      --arg protocol "vless" \
      --arg name "$node_name" \
      --arg address "$server_address" \
      --arg port "$server_port" \
      --arg id "$user_info" \
      --arg params "?${params%#*}" \
      '{protocol: $protocol, name: $name, address: $address, port: $port, id: $id, params: $params}'
}

# Parse a Clash YAML file and convert proxies to our standard JSON format
parse_clash_yaml() {
    local file_path=$1
    # Use yq to extract proxy information and format it as JSON lines
    # This example is simplified and assumes vless proxies. A real-world scenario would need more complex logic.
    yq e '.proxies[] | select(.type == "vless") | {protocol: .type, name: .name, address: .server, port: .port, id: .uuid, params: ("?type=" + .network + "&security=" + .tls + "&sni=" + .servername)}' "$file_path"
}


# --- Main Logic ---

# Check for input
if [ -z "$1" ]; then
    print_error "Usage: $0 <subscription_url_or_filepath>"
    exit 1
fi

INPUT=$1
RAW_CONTENT=""

# 1. Get raw content based on input type
if [[ "$INPUT" == http* ]]; then
    # It's a URL, download and decode
    RAW_CONTENT=$(curl -sL "$INPUT" | base64 --decode)
    if [ -z "$RAW_CONTENT" ]; then
        print_error "Failed to download or decode subscription from URL."
        exit 1
    fi
elif [[ "$INPUT" == *.yaml || "$INPUT" == *.yml ]]; then
    # It's a YAML file
    if [ ! -f "$INPUT" ]; then
        print_error "File not found: $INPUT"
        exit 1
    fi
    # YAML parsing is handled by its own function
    parse_clash_yaml "$INPUT" | jq -c '.' # Ensure each JSON object is on a new line
    exit 0 # Exit after handling YAML
else
    # Assume it's a file with links
    if [ ! -f "$INPUT" ]; then
        print_error "File not found: $INPUT"
        exit 1
    fi
    RAW_CONTENT=$(cat "$INPUT")
fi

# 2. Parse the raw content line by line
NODES_JSON="[]"
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    if [[ "$line" == vless://* ]]; then
        NODE_JSON=$(parse_vless_link "$line")
        NODES_JSON=$(echo "$NODES_JSON" | jq --argjson node "$NODE_JSON" '. + [$node]')
    # Add elif for vmess://, trojan:// etc. here in the future
    fi
done <<< "$RAW_CONTENT"

# 3. Output the final JSON array
echo "$NODES_JSON"
