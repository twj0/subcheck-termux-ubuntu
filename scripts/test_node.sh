#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
XRAY_BIN="../xray/xray" # Relative path to the xray binary
CONFIG_FILE="temp_config.json"
LOG_FILE="xray_temp.log"
SOCKS_PORT=10808
LATENCY_URL="http://www.google.com/gen_204"
CURL_TIMEOUT=10 # seconds

# --- Helper Functions ---
print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

cleanup() {
    # Kill the xray process if it's running
    if [ ! -z "$XRAY_PID" ] && ps -p $XRAY_PID > /dev/null; then
        kill $XRAY_PID
    fi
    # Remove temporary files
    rm -f $CONFIG_FILE $LOG_FILE
}

# Set trap to run cleanup function on script exit
trap cleanup EXIT

# --- Main Logic ---

# 1. Check for input
if [ -z "$1" ]; then
    print_error "Usage: $0 <node_json>"
    exit 1
fi

NODE_JSON=$1
NODE_NAME=$(echo "$NODE_JSON" | jq -r '.name')

# Function to generate a failure JSON output
generate_failure_output() {
    jq -n \
      --arg name "$NODE_NAME" \
      '{name: $name, success: false, latency: -1, download: -1, upload: -1, error: $1}'
}

# 2. Generate Xray config from node JSON
# This is a simplified config generator for VLESS + TCP + TLS
ADDRESS=$(echo "$NODE_JSON" | jq -r '.address')
PORT=$(echo "$NODE_JSON" | jq -r '.port')
ID=$(echo "$NODE_JSON" | jq -r '.id')
# A very basic way to get SNI from params, assuming format is ?...&sni=...
SNI=$(echo "$NODE_JSON" | jq -r '.params' | grep -o 'sni=[^&]*' | cut -d= -f2)
[ -z "$SNI" ] && SNI=$ADDRESS # Fallback SNI to address if not found

cat > $CONFIG_FILE <<- EOM
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_FILE"
  },
  "inbounds": [
    {
      "port": $SOCKS_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$ADDRESS",
            "port": $PORT,
            "users": [
              {
                "id": "$ID",
                "flow": "xtls-rprx-direct"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$SNI"
        }
      }
    }
  ]
}
EOM

# 3. Start Xray
$XRAY_BIN -c $CONFIG_FILE > /dev/null 2>&1 &
XRAY_PID=$!
sleep 2 # Give xray time to start

# Check if Xray process is running
if ! ps -p $XRAY_PID > /dev/null; then
    generate_failure_output "Failed to start Xray core."
    exit 1
fi

# 4. Test Latency
LATENCY_RESULT=$(curl -s -o /dev/null --socks5-hostname localhost:$SOCKS_PORT -w "%{time_connect}" --connect-timeout $CURL_TIMEOUT "$LATENCY_URL" || echo "timeout")

if [ "$LATENCY_RESULT" == "timeout" ] || [ -z "$LATENCY_RESULT" ]; then
    generate_failure_output "Latency test failed (timeout or error)."
    exit 1
fi
# Convert to milliseconds
LATENCY_MS=$(echo "$LATENCY_RESULT * 1000" | bc | cut -d. -f1)


# 5. Test Speed
# Use a try-catch block for speedtest-cli as it can be flaky
SPEED_RESULT=""
SPEED_ERROR="false"
SPEED_RESULT=$(speedtest-cli --proxy socks5://127.0.0.1:$SOCKS_PORT --simple) || SPEED_ERROR="true"

if [ "$SPEED_ERROR" == "true" ]; then
    generate_failure_output "Speedtest failed."
    exit 1
fi

DOWNLOAD_SPEED=$(echo "$SPEED_RESULT" | grep "Download" | awk '{print $2}')
UPLOAD_SPEED=$(echo "$SPEED_RESULT" | grep "Upload" | awk '{print $2}')

# 6. Output result as JSON
jq -n \
  --arg name "$NODE_NAME" \
  --argjson success true \
  --argjson latency "$LATENCY_MS" \
  --argjson download "$DOWNLOAD_SPEED" \
  --argjson upload "$UPLOAD_SPEED" \
  '{name: $name, success: $success, latency: $latency, download: $download, upload: $upload, error: null}'

# The trap will handle cleanup
exit 0