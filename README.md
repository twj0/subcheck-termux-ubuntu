# SubsCheck for Termux/Ubuntu

A lightweight, script-based proxy node checker designed to run in resource-constrained environments like Termux on Android, without needing Docker.

This project is inspired by the ideas discussed and aims to provide a simple, yet powerful tool for automated node testing.

## Features

-   Parses various subscription formats (Base64, Clash YAML).
-   Tests node latency and connectivity.
-   Tests node download speed.
-   Lightweight and script-based, perfect for headless Linux environments.
-   Designed for ARM-based devices like Android phones.

## Project Structure

```
.
├── main.sh             # Main executable script
├── scripts/
│   ├── parse.sh        # Script for parsing subscriptions
│   └── test_node.sh    # Script for testing a single node
├── xray/               # Directory for the Xray-core binary
│   └── xray            # (You need to download the ARM version yourself)
├── config_example.yaml # An example Clash configuration file
└── README.md           # This file
```

## How to Use

1.  **Prerequisites**: Make sure you have `curl`, `wget`, `jq`, `yq`, and `speedtest-cli` installed in your Termux Ubuntu environment.
    ```bash
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget jq speedtest-cli
    sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq
    ```

2.  **Download Xray-core**: Download the appropriate ARM version of Xray-core from the [official releases page](https://github.com/XTLS/Xray-core/releases) and place the `xray` executable in the `xray/` directory.
    ```bash
    # Example for arm64-v8a
    mkdir -p xray
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-arm64-v8a.zip
    unzip Xray-linux-arm64-v8a.zip -d xray
    chmod +x xray/xray
    ```

3.  **Make scripts executable**:
    ```bash
    chmod +x main.sh scripts/*.sh
    ```

4.  **Run the check**:
    ```bash
    # From a subscription link
    ./main.sh "YOUR_SUBSCRIPTION_LINK"

    # From a local Clash config file
    ./main.sh /path/to/your/config.yaml
    ```

## Automation with Cron

To run the check automatically every day at 3 AM, for example:

1.  Open the cron table for editing:
    ```bash
    crontab -e
    ```

2.  Add the following line, making sure to use the absolute path to your `main.sh` script:
    ```
    0 3 * * * /path/to/your/subcheck-termux-ubuntu/main.sh "YOUR_SUBSCRIPTION_LINK" > /path/to/your/subcheck-termux-ubuntu/cron.log 2>&1
    ```
This will run the script and save its output to `cron.log`.