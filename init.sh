#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# --- Main Script ---

# 1. Update package list and install dependencies
print_info "Updating package list and installing dependencies..."
if sudo apt-get update && sudo apt-get install -y git curl wget jq speedtest-cli unzip; then
    print_info "Dependencies installed successfully."
else
    print_error "Failed to install dependencies. Please check your network connection and permissions."
    exit 1
fi

# 2. Install yq for YAML parsing
print_info "Installing yq for YAML parsing..."
if sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq; then
    print_info "yq installed successfully."
else
    print_error "Failed to install yq."
    exit 1
fi

# 3. Check and install Xray-core
XRAY_DIR="xray"
XRAY_BIN="$XRAY_DIR/xray"

if [ -f "$XRAY_BIN" ]; then
    print_info "Xray-core already exists. Skipping installation."
else
    print_info "Xray-core not found. Downloading and installing..."
    
    # Create directory
    mkdir -p $XRAY_DIR
    
    # Fetch the latest release URL for linux-arm64-v8a
    LATEST_URL=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.assets[] | select(.name | test("linux-arm64-v8a.zip$")) | .browser_download_url')
    
    if [ -z "$LATEST_URL" ]; then
        print_error "Could not find the latest Xray-core release for linux-arm64-v8a. Please check the repository manually."
        rm -rf $XRAY_DIR
        exit 1
    fi
    
    # Add ghproxy.com for users in mainland China
    PROXY_URL="https://ghfast.top/$LATEST_URL"
    
    print_info "Downloading from (via proxy): $PROXY_URL"
    
    # Download and unzip
    wget -qO xray.zip "$PROXY_URL"
    unzip -o xray.zip -d $XRAY_DIR
    
    # Clean up
    rm xray.zip
    
    # Verify installation
    if [ -f "$XRAY_BIN" ]; then
        chmod +x "$XRAY_BIN"
        print_info "Xray-core installed successfully in '$XRAY_DIR' directory."
    else
        print_error "Xray-core installation failed. The 'xray' binary was not found after extraction."
        rm -rf $XRAY_DIR
        exit 1
    fi
fi

# 4. Make other scripts executable
print_info "Making shell scripts executable..."
chmod +x main.sh
chmod +x scripts/parse.sh
chmod +x scripts/test_node.sh
chmod +x init.sh

# 5. Verify script permissions
print_info "Verifying script permissions..."
if [ -x "main.sh" ] && [ -x "scripts/parse.sh" ] && [ -x "scripts/test_node.sh" ]; then
    print_info "All scripts have execute permissions."
else
    print_error "Some scripts may not have proper execute permissions."
fi

print_info "Initialization complete! You can now run the main script."
