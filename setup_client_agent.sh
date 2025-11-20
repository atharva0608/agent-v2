#!/bin/bash

###############################################################################
# Client Agent Setup Script
# Installs and configures the supportive client agent
###############################################################################

set -e

echo "======================================================================="
echo "Client Agent Setup Script"
echo "======================================================================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Do not run this script as root!"
    echo "Run as a regular user with sudo privileges."
    exit 1
fi

# Collect configuration
echo "=== Configuration ==="
echo ""

read -p "Enter Central Server URL (e.g., http://localhost:5000): " CENTRAL_SERVER_URL
read -p "Enter Client Token: " CLIENT_TOKEN
read -p "Enter Client ID: " CLIENT_ID

echo ""
echo "Configuration:"
echo "  Central Server: $CENTRAL_SERVER_URL"
echo "  Client ID: $CLIENT_ID"
echo ""
read -p "Is this correct? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "Setup cancelled."
    exit 0
fi

# Detect OS
echo ""
echo "=== Detecting OS ==="
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    echo "Detected OS: $OS"
else
    echo "ERROR: Cannot detect OS"
    exit 1
fi

# Install dependencies
echo ""
echo "=== Installing Dependencies ==="

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Installing Python 3 and dependencies..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
    echo "Installing Python 3 and dependencies..."
    sudo yum install -y python3 python3-pip
else
    echo "WARNING: Unsupported OS. Assuming Python 3 is installed."
fi

# Create directory structure
echo ""
echo "=== Creating Directory Structure ==="

INSTALL_DIR="/opt/client-agent"
LOG_DIR="/var/log/client-agent"
CONFIG_DIR="/etc/client-agent"

sudo mkdir -p $INSTALL_DIR
sudo mkdir -p $LOG_DIR
sudo mkdir -p $CONFIG_DIR

echo "✓ Created $INSTALL_DIR"
echo "✓ Created $LOG_DIR"
echo "✓ Created $CONFIG_DIR"

# Create virtual environment
echo ""
echo "=== Creating Python Virtual Environment ==="

sudo python3 -m venv $INSTALL_DIR/venv
echo "✓ Virtual environment created"

# Install Python packages
echo ""
echo "=== Installing Python Packages ==="

sudo $INSTALL_DIR/venv/bin/pip install --upgrade pip
sudo $INSTALL_DIR/venv/bin/pip install requests python-dotenv

echo "✓ Python packages installed"

# Copy agent script
echo ""
echo "=== Installing Client Agent ==="

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
sudo cp $SCRIPT_DIR/client_agent.py $INSTALL_DIR/
sudo chmod +x $INSTALL_DIR/client_agent.py

echo "✓ Client agent installed to $INSTALL_DIR"

# Create configuration file
echo ""
echo "=== Creating Configuration ==="

sudo bash -c "cat > $CONFIG_DIR/.env" <<EOF
# Client Agent Configuration
CENTRAL_SERVER_URL=$CENTRAL_SERVER_URL
CLIENT_TOKEN=$CLIENT_TOKEN
CLIENT_ID=$CLIENT_ID

# Timing Configuration
STATUS_UPDATE_INTERVAL=10
DATA_FETCH_INTERVAL=15
SWITCH_CHECK_INTERVAL=5
EOF

sudo chmod 600 $CONFIG_DIR/.env
echo "✓ Configuration saved to $CONFIG_DIR/.env"

# Create systemd service
echo ""
echo "=== Creating Systemd Service ==="

sudo bash -c "cat > /etc/systemd/system/client-agent.service" <<EOF
[Unit]
Description=Client Agent for Spot Optimizer
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$CONFIG_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/client_agent.py
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/client_agent.log
StandardError=append:$LOG_DIR/client_agent.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable client-agent.service

echo "✓ Systemd service created and enabled"

# Create helper scripts
echo ""
echo "=== Creating Helper Scripts ==="

# Status script
sudo bash -c "cat > /usr/local/bin/client-agent-status" <<'EOF'
#!/bin/bash
systemctl status client-agent.service
EOF
sudo chmod +x /usr/local/bin/client-agent-status

# Logs script
sudo bash -c "cat > /usr/local/bin/client-agent-logs" <<'EOF'
#!/bin/bash
tail -f /var/log/client-agent/client_agent.log
EOF
sudo chmod +x /usr/local/bin/client-agent-logs

# Restart script
sudo bash -c "cat > /usr/local/bin/client-agent-restart" <<'EOF'
#!/bin/bash
sudo systemctl restart client-agent.service
echo "Client agent restarted"
EOF
sudo chmod +x /usr/local/bin/client-agent-restart

echo "✓ Helper scripts created:"
echo "  - client-agent-status"
echo "  - client-agent-logs"
echo "  - client-agent-restart"

# Test connection
echo ""
echo "=== Testing Connection to Central Server ==="

TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $CLIENT_TOKEN" \
    "$CENTRAL_SERVER_URL/api/clients/$CLIENT_ID" || echo "000")

if [ "$TEST_RESPONSE" = "200" ]; then
    echo "✓ Successfully connected to central server"
elif [ "$TEST_RESPONSE" = "401" ]; then
    echo "⚠ Authentication failed - check your token"
elif [ "$TEST_RESPONSE" = "404" ]; then
    echo "⚠ Client ID not found on server"
elif [ "$TEST_RESPONSE" = "000" ]; then
    echo "⚠ Cannot reach central server - check URL"
else
    echo "⚠ Received HTTP $TEST_RESPONSE from server"
fi

# Start service
echo ""
echo "=== Starting Client Agent ==="

sudo systemctl start client-agent.service

sleep 2

if sudo systemctl is-active --quiet client-agent.service; then
    echo "✓ Client agent is running"
else
    echo "✗ Client agent failed to start"
    echo "Check logs with: client-agent-logs"
    exit 1
fi

# Summary
echo ""
echo "======================================================================="
echo "✓ Client Agent Setup Complete!"
echo "======================================================================="
echo ""
echo "The client agent is now running and will:"
echo "  • Fetch data from central server every 15 seconds"
echo "  • Check for pending switches every 5 seconds"
echo "  • Send status updates every 10 seconds"
echo ""
echo "Useful commands:"
echo "  client-agent-status   - Check agent status"
echo "  client-agent-logs     - View live logs"
echo "  client-agent-restart  - Restart agent"
echo ""
echo "Logs are available at: $LOG_DIR/client_agent.log"
echo "Configuration: $CONFIG_DIR/.env"
echo ""
echo "======================================================================="
