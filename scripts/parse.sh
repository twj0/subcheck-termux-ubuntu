#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---
print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# Function to URL-decode strings
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
    
    # If node name is empty, use server address as fallback
    [ -z "$node_name" ] && node_name="$server_address:$server_port"
    
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

# Parse a single vmess:// link and convert to JSON
parse_vmess_link() {
    local link=$1
    # Remove "vmess://" prefix and decode base64
    local encoded_config=${link#vmess://}
    local decoded_config=$(echo "$encoded_config" | base64 --decode 2>/dev/null || echo "{}")
    
    # Extract fields using jq
    local address=$(echo "$decoded_config" | jq -r '.add // empty')
    local port=$(echo "$decoded_config" | jq -r '.port // empty')
    local id=$(echo "$decoded_config" | jq -r '.id // empty')
    local name=$(echo "$decoded_config" | jq -r '.ps // empty')
    
    # If any required field is missing, return empty
    if [ -z "$address" ] || [ -z "$port" ] || [ -z "$id" ]; then
        return
    fi
    
    # If name is empty, use server address as fallback
    [ -z "$name" ] && name="$address:$port"
    
    # Use jq to safely construct a JSON object
    jq -n \
      --arg protocol "vmess" \
      --arg name "$name" \
      --arg address "$address" \
      --arg port "$port" \
      --arg id "$id" \
      --arg params "" \
      '{protocol: $protocol, name: $name, address: $address, port: $port, id: $id, params: $params}'
}

# Parse a Clash YAML file and convert proxies to our standard JSON format
parse_clash_yaml() {
    local file_path=$1
    yq e '.proxies[] | select(.type == "vless") | {protocol: .type, name: .name, address: .server, port: .port, id: .uuid, params: ("?type=" + .network + "&security=" + .tls + "&sni=" + .servername)}' "$file_path"
}


# --- Main Logic ---

if [ -z "$1" ]; then
    print_error "Usage: $0 <subscription_url_or_filepath>"
    exit 1
fi

INPUT=$1
RAW_CONTENT=""

# 1. Get raw content based on input type
if [[ "$INPUT" == http* ]]; then
    # It's a URL, check for GitHub and apply proxy if needed
    local url="$INPUT"
    if [[ "$url" == *"github.com"* ]] || [[ "$url" == *"githubusercontent.com"* ]]; then
        echo "[INFO] Using GitHub proxy for URL: $url" >&2
        url="https://ghfast.top/${url}"
    fi
    
    # Download content with timeout
    DOWNLOADED_CONTENT=$(curl -sL --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
    if [ -z "$DOWNLOADED_CONTENT" ]; then
        print_error "Failed to download subscription from URL: $INPUT (timeout or network error)"
        exit 1
    fi
    # Check if the content is likely Base64. A simple check is to see if it's one long line without spaces.
    # And does not contain protocol schemes like vless://
    if [[ "$DOWNLOADED_CONTENT" != *" "* && "$DOWNLOADED_CONTENT" != *"vless://"* && "$DOWNLOADED_CONTENT" != *"vmess://"* ]]; then
        RAW_CONTENT=$(echo "$DOWNLOADED_CONTENT" | base64 --decode --ignore-garbage)
    else
        # It's likely plain text
        RAW_CONTENT="$DOWNLOADED_CONTENT"
    fi
elif [[ "$INPUT" == *.yaml || "$INPUT" == *.yml ]]; then
    if [ ! -f "$INPUT" ]; then
        print_error "File not found: $INPUT"
        exit 1
    fi
    parse_clash_yaml "$INPUT" | jq -c '.'
    exit 0
else
    if [ ! -f "$INPUT" ]; then
        print_error "File not found: $INPUT"
        exit 1
    fi
    RAW_CONTENT=$(cat "$INPUT")
fi

# 2. Parse the raw content line by line
NODES_JSON="[]"
LINE_COUNT=0
PARSED_COUNT=0

echo "[INFO] Parsing subscription content..." >&2

while IFS= read -r line; do
    [ -z "$line" ] && continue
    LINE_COUNT=$((LINE_COUNT + 1))

    if [[ "$line" == vless://* ]]; then
        NODE_JSON=$(parse_vless_link "$line" 2>/dev/null)
        if [ ! -z "$NODE_JSON" ]; then
            NODES_JSON=$(echo "$NODES_JSON" | jq --argjson node "$NODE_JSON" '. + [$node]' 2>/dev/null)
            PARSED_COUNT=$((PARSED_COUNT + 1))
        fi
    elif [[ "$line" == vmess://* ]]; then
        NODE_JSON=$(parse_vmess_link "$line" 2>/dev/null)
        if [ ! -z "$NODE_JSON" ]; then
            NODES_JSON=$(echo "$NODES_JSON" | jq --argjson node "$NODE_JSON" '. + [$node]' 2>/dev/null)
            PARSED_COUNT=$((PARSED_COUNT + 1))
        fi
    fi
done <<< "$RAW_CONTENT"

echo "[INFO] Parsed $PARSED_COUNT nodes from $LINE_COUNT lines" >&2

# 3. Output the final JSON array
echo "$NODES_JSON"
