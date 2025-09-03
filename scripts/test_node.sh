#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
XRAY_BIN="./xray/xray" # Relative path to the xray binary
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
    local error_msg="$1"
    jq -n \
      --arg name "$NODE_NAME" \
      --arg error "$error_msg" \
      '{name: $name, success: false, latency: -1, download: -1, upload: -1, error: $error}'
}

# 2. Generate Xray config from node JSON
ADDRESS=$(echo "$NODE_JSON" | jq -r '.address')
PORT=$(echo "$NODE_JSON" | jq -r '.port')
ID=$(echo "$NODE_JSON" | jq -r '.id')
PROTOCOL=$(echo "$NODE_JSON" | jq -r '.protocol')

# A very basic way to get SNI from params, assuming format is ?...&sni=...
SNI=$(echo "$NODE_JSON" | jq -r '.params' | grep -o 'sni=[^&]*' | cut -d= -f2 2>/dev/null || echo "")
[ -z "$SNI" ] && SNI=$ADDRESS # Fallback SNI to address if not found

# Generate config based on protocol
if [ "$PROTOCOL" == "vless" ]; then
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
                "encryption": "none"
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
elif [ "$PROTOCOL" == "vmess" ]; then
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
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "$ADDRESS",
            "port": $PORT,
            "users": [
              {
                "id": "$ID",
                "alterId": 0
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
else
    generate_failure_output "Unsupported protocol: $PROTOCOL"
    exit 1
fi

# 3. Check if Xray binary exists
if [ ! -f "$XRAY_BIN" ]; then
    generate_failure_output "Xray binary not found at $XRAY_BIN. Please run init.sh first."
    exit 1
fi

# Start Xray
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
# Convert to milliseconds (avoid bc dependency)
LATENCY_MS=$(awk "BEGIN {printf \"%.0f\", $LATENCY_RESULT * 1000}" 2>/dev/null || echo "0")


# 5. Test Speed (simplified without proxy support)
# Many speedtest-cli versions don't support --proxy, so we'll use a simple download test
SPEED_ERROR="false"
DOWNLOAD_SPEED="0"
UPLOAD_SPEED="0"

# Try a simple download speed test through the proxy
DOWNLOAD_TEST_URL="http://speedtest.ftp.otenet.gr/files/test1Mb.db"
DOWNLOAD_START=$(date +%s.%N)
DOWNLOAD_RESULT=$(curl -s -o /dev/null --socks5-hostname localhost:$SOCKS_PORT --connect-timeout 10 --max-time 30 -w "%{size_download}" "$DOWNLOAD_TEST_URL" 2>/dev/null || echo "0")
DOWNLOAD_END=$(date +%s.%N)

if [ "$DOWNLOAD_RESULT" != "0" ] && [ ! -z "$DOWNLOAD_RESULT" ]; then
    # Calculate speed in Mbps
    DOWNLOAD_TIME=$(awk "BEGIN {printf \"%.2f\", $DOWNLOAD_END - $DOWNLOAD_START}" 2>/dev/null || echo "0")
    if [ "$DOWNLOAD_TIME" != "0.00" ] && [ "$DOWNLOAD_TIME" != "0" ]; then
        DOWNLOAD_SPEED=$(awk "BEGIN {printf \"%.2f\", ($DOWNLOAD_RESULT * 8) / ($DOWNLOAD_TIME * 1000000)}" 2>/dev/null || echo "0")
    fi
fi

# Skip upload test for now as it's more complex without proper speedtest proxy support

# 6. Output result as JSON (ensure proper number formatting)
jq -n \
  --arg name "$NODE_NAME" \
  --arg latency "$LATENCY_MS" \
  --arg download "$DOWNLOAD_SPEED" \
  --arg upload "$UPLOAD_SPEED" \
  '{name: $name, success: true, latency: ($latency | tonumber), download: ($download | tonumber), upload: ($upload | tonumber), error: null}'

# The trap will handle cleanup
exit 0