#!/bin/bash

# SubsCheck Termux/Ubuntu Version
# Node testing script

# --- Input ---
# $1: Standardized node information (JSON format)
# $2: Path to the xray executable
# $3: Path to the temporary directory

NODE_INFO="$1"
XRAY_PATH="$2"
TEMP_DIR="$3"

# --- Configuration ---
LOCAL_SOCKS_PORT=10808
TEST_URL="http://www.google.com/gen_204"
CONFIG_FILE="$TEMP_DIR/xray_config.json"
XRAY_LOG_FILE="$TEMP_DIR/xray.log"
XRAY_PID_FILE="$TEMP_DIR/xray.pid"

# --- Functions ---
generate_config() {
    # This function generates a valid xray client config from the standardized NODE_INFO JSON.
    # This is a complex part and depends heavily on the output of parse.sh
    # This is a basic vmess example. It needs to be extended for vless, trojan etc.
    
    SERVER=$(echo "$NODE_INFO" | jq -r .server)
    PORT=$(echo "$NODE_INFO" | jq -r .port)
    TYPE=$(echo "$NODE_INFO" | jq -r .type)
    UUID=$(echo "$NODE_INFO" | jq -r .uuid)
    ALTERID=$(echo "$NODE_INFO" | jq -r .alterId)
    CIPHER=$(echo "$NODE_INFO" | jq -r .cipher)
    TLS=$(echo "$NODE_INFO" | jq -r .tls)
    NETWORK=$(echo "$NODE_INFO" | jq -r .network)

    # Basic validation
    if [ -z "$SERVER" ] || [ -z "$PORT" ] || [ -z "$UUID" ]; then
        echo "{\"name\": \"$(echo "$NODE_INFO" | jq -r .name)\", \"status\": \"error\", \"reason\": \"Invalid node info\"}"
        exit 1
    fi

    TLS_SETTINGS="\"tls\""
    if [ "$TLS" = "true" ]; then
        TLS_SETTINGS="\"tls\""
    else
        TLS_SETTINGS="\"none\""
    fi

    # Create a minimal config
    cat > "$CONFIG_FILE" << EOL
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $LOCAL_SOCKS_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "$TYPE",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER",
            "port": $PORT,
            "users": [
              {
                "id": "$UUID",
                "alterId": $ALTERID,
                "security": "$CIPHER"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "$NETWORK",
        "security": $TLS_SETTINGS
      }
    }
  ]
}
EOL
}

start_xray() {
    if [ ! -f "$XRAY_PATH" ]; then
        echo "{\"name\": \"$(echo "$NODE_INFO" | jq -r .name)\", \"status\": \"error\", \"reason\": \"Xray executable not found at $XRAY_PATH\"}"
        exit 1
    fi
    
    "$XRAY_PATH" -c "$CONFIG_FILE" > "$XRAY_LOG_FILE" 2>&1 &
    echo $! > "$XRAY_PID_FILE"
    sleep 2 # Give xray some time to start
}

stop_xray() {
    if [ -f "$XRAY_PID_FILE" ]; then
        kill "$(cat "$XRAY_PID_FILE")"
        rm "$XRAY_PID_FILE"
    fi
}

# --- Main Logic ---
# Ensure cleanup happens on exit
trap stop_xray EXIT

# 1. Generate config
generate_config

# 2. Start Xray
start_xray

# 3. Test Latency
LATENCY_RESULT=$(curl -s -o /dev/null --socks5-hostname localhost:$LOCAL_SOCKS_PORT -w "%{time_connect}" "$TEST_URL")
CURL_EXIT_CODE=$?

if [ $CURL_EXIT_CODE -ne 0 ]; then
    echo "{\"name\": \"$(echo "$NODE_INFO" | jq -r .name)\", \"status\": \"failed\", \"latency\": -1, \"speed_mbps\": 0}"
    exit 0
fi

LATENCY_MS=$(echo "$LATENCY_RESULT * 1000" | bc | cut -d. -f1)

# 4. Test Speed
# The --proxy flag is essential here
SPEED_TEST_RESULT=$(speedtest-cli --proxy socks5://127.0.0.1:$LOCAL_SOCKS_PORT --simple)
if [ $? -ne 0 ]; then
    DOWNLOAD_SPEED="0"
else
    DOWNLOAD_SPEED=$(echo "$SPEED_TEST_RESULT" | grep "Download:" | awk '{print $2}')
fi

# 5. Output result as JSON
echo "{\"name\": \"$(echo "$NODE_INFO" | jq -r .name)\", \"status\": \"success\", \"latency_ms\": $LATENCY_MS, \"speed_mbps\": \"$DOWNLOAD_SPEED\"}"

exit 0