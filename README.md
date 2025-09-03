# SubCheck Termux Ubuntu

A lightweight node checking service optimized for Termux Ubuntu environment on constrained devices, with special optimizations for China mainland network conditions.

## Features

- **Multi-protocol Support**: VLESS, VMess, and Clash YAML format parsing
- **China Network Optimized**: DNS optimization and GitHub proxy support
- **Lightweight Design**: Minimal dependencies, suitable for old phones
- **Multiple Testing Modes**: Full test, simplified test, and quick test
- **VPS Deployment**: Automated deployment script for Ubuntu VPS
- **Configuration Driven**: YAML configuration support
- **Multiple Output Formats**: JSON, YAML, and Base64 encoding
- **Termux Scheduler**: Automated scheduled testing with web interface
- **System Service**: Background daemon with systemd integration
- **Web Management**: Modern web interface for remote monitoring

## Quick Start

### 1. Termux Environment Setup (Recommended)

For Termux + Ubuntu24 environment:

```bash
# One-click setup for Termux
bash termux_setup.sh

# Start the service
bash start_subcheck.sh
```

This will:
- Apply Termux-specific optimizations
- Install dependencies
- Configure network optimization
- Setup auto-start
- Launch web interface at http://localhost:8080

### 2. Manual Setup

```bash
# Install dependencies and download core
bash init.sh

# Quick connectivity test (first 3 nodes)
bash quick_test.sh

# Simplified China-optimized test
bash simple_china_test.sh
```

### 3. Scheduled Testing

```bash
# Install as system service
bash termux_scheduler.sh install

# Start scheduled testing
bash termux_scheduler.sh start

# Check status
bash termux_scheduler.sh status
```

## New Termux Features

### Termux Scheduler (`termux_scheduler.sh`)

Based on SubsCheck-Win-GUI architecture, provides:

- **Scheduled Testing**: Configurable intervals (default: 2 hours for Termux)
- **Web Interface**: Modern dashboard at http://localhost:8080
- **Result Storage**: Automatic result archiving and cleanup
- **Notifications**: Telegram bot support
- **System Integration**: Systemd service support

**Commands:**
```bash
bash termux_scheduler.sh daemon    # Run in background
bash termux_scheduler.sh test      # Single test
bash termux_scheduler.sh install   # Install system service
bash termux_scheduler.sh status    # Show status
bash termux_scheduler.sh config    # Edit configuration
```

### Termux Optimizations

- **Low Power Mode**: Reduced CPU usage and testing frequency
- **Mobile Network**: Extended timeouts for unstable connections
- **Memory Efficient**: Lower concurrency for constrained devices
- **Auto-start**: Automatic service startup on boot

### Web Interface Features

- **Real-time Status**: Live monitoring of testing progress
- **Historical Results**: Browse past test results
- **Manual Testing**: Trigger tests on demand
- **Log Viewer**: Real-time log monitoring
- **Mobile Responsive**: Optimized for phone screens

## Testing Scripts

### `quick_test.sh`
- **Purpose**: Super fast connectivity check
- **Features**: Tests first 3 nodes only, basic TCP connectivity
- **Use case**: Quick verification of subscription and basic functionality

### `simple_china_test.sh`
- **Purpose**: China mainland network optimized testing
- **Features**: DNS optimization, GitHub proxy, robust parsing
- **Use case**: Regular testing in China network environment

### `china_optimized.sh`
- **Purpose**: Full-featured China optimized testing
- **Features**: Complete node testing with speed measurement
- **Use case**: Comprehensive node evaluation

### `termux_scheduler.sh` 
- **Purpose**: Automated scheduled testing service
- **Features**: Web interface, notifications, result storage
- **Use case**: Continuous monitoring and scheduled testing

## Configuration

### Scheduler Configuration (`~/.subcheck/scheduler.conf`)

```bash
# Testing interval (seconds)
INTERVAL=7200              # 2 hours (Termux optimized)

# Concurrency (reduced for mobile)
CONCURRENT=5               # Lower for phones

# Timeouts (extended for mobile networks)
TIMEOUT=45                 # Increased for unstable connections

# Web interface
ENABLE_WEB=true
WEB_PORT=8080

# Notifications
ENABLE_NOTIFICATION=false
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Result retention
KEEP_DAYS=7
```

### Node Testing Configuration (`config.yaml`)

```yaml
# Testing parameters
concurrent: 5               # Reduced for Termux
timeout: 45                 # Extended for mobile networks
output_format: "json"

# Filtering
min_speed: 1.0
max_latency: 2000

# Network optimization
use_github_proxy: true
dns_servers:
  - "223.5.5.5"
  - "119.29.29.29"
```

## Termux Management Commands

### Service Management
```bash
# Start service
bash start_subcheck.sh start

# Check status
bash start_subcheck.sh status

# View logs
bash start_subcheck.sh logs

# Stop service
bash start_subcheck.sh stop

# Manual test
bash start_subcheck.sh test
```

### Web Interface Access
- **Local**: http://localhost:8080
- **Network**: http://[phone-ip]:8080 (if accessible)

## Network Optimizations

### DNS Configuration
- Primary: 223.5.5.5 (Alibaba)
- Secondary: 119.29.29.29 (Tencent)
- Fallback: 114.114.114.114, 8.8.8.8

### GitHub Proxy
- Uses `https://ghfast.top/` for GitHub API and downloads
- Automatic fallback to direct connection
- Improves reliability in China mainland

### Termux-Specific Optimizations
- **Power Saving**: CPU governor optimization
- **Process Priority**: Lower priority for background operation
- **Network Buffering**: Optimized for mobile networks

## Dependencies

### Required
- `curl` - HTTP requests
- `jq` - JSON processing
- `python3` - Web interface
- `base64` - Encoding/decoding

### Optional
- `yq` - YAML processing
- `unzip` - Archive extraction
- `speedtest-cli` - Speed testing
- `xray` - Core proxy engine

## Installation Methods

### Method 1: Termux One-Click Setup 
```bash
bash termux_setup.sh
bash start_subcheck.sh
```

### Method 2: System Service Installation
```bash
bash termux_scheduler.sh install
systemctl start subcheck-scheduler
```

### Method 3: VPS Deployment
```bash
bash deploy_vps.sh user@your-vps-ip
```

## Troubleshooting

### Termux-Specific Issues

1. **Service Won't Start**
   ```bash
   # Check permissions
   chmod +x *.sh
   
   # Check dependencies
   pkg install curl jq python
   ```

2. **Web Interface Not Accessible**
   ```bash
   # Check if port is in use
   netstat -tlnp | grep 8080
   
   # Try different port
   export WEB_PORT=8081
   bash start_subcheck.sh restart
   ```

3. **Auto-start Not Working**
   ```bash
   # Check Termux:Boot app is installed
   # Verify boot script permissions
   ls -la ~/.termux/boot/
   ```

### Performance Issues
- Reduce `CONCURRENT` value in config
- Increase `TIMEOUT` for slow networks
- Enable power saving mode

## Project Structure

```bash
subcheck-termux-ubuntu/
├── main.sh                    # Main testing script
├── init.sh                    # Environment initialization
├── quick_test.sh              # Quick connectivity test
├── simple_china_test.sh       # Simplified China-optimized test
├── china_optimized.sh         # Full China-optimized test
├── deploy_vps.sh              # VPS deployment script
├── termux_scheduler.sh        #  Scheduled testing service
├── termux_setup.sh            #  Termux environment setup
├── start_subcheck.sh          #  Service management script
├── network_optimize.sh        #  Network optimization
├── config.yaml                # Node testing configuration
├── subscription.txt           # Subscription URLs
├── scripts/
│   ├── parse.sh              # Node parsing logic
│   └── test_node.sh          # Single node testing
└── README.md                 # This file

# Runtime directories (created automatically)
~/.subcheck/
├── scheduler.conf            # Scheduler configuration
├── subscriptions.txt         # User subscriptions
├── logs/                     # Test logs
└── results/                  # Test results
```

## Architecture

Based on **SubsCheck-Win-GUI** design principles:

- **Modular Design**: Separate components for parsing, testing, scheduling
- **Configuration-Driven**: Flexible configuration system
- **Web Interface**: Modern dashboard for monitoring
- **Background Service**: Reliable daemon operation
- **Result Storage**: Persistent result archiving
- **Notification System**: Alert mechanisms

## License

This project is for educational and research purposes only. Users are responsible for compliance with local laws and regulations.

## Contributing

Contributions are welcome! Please ensure:
- Code follows shell scripting best practices
- Changes are tested in Termux environment
- Termux-specific optimizations are maintained
- Documentation is updated accordingly

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review debug logs: `bash start_subcheck.sh logs`
3. Test with simplified scripts first: `bash quick_test.sh`
4. Verify Termux environment: `bash termux_setup.sh`
