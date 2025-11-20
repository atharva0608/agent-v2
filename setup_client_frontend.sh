#!/bin/bash

###############################################################################
# Client Frontend Setup Script
# Installs and configures the client-centric frontend on port 80
###############################################################################

set -e

echo "======================================================================="
echo "Client Frontend Setup Script"
echo "======================================================================="
echo ""

# Check if running as root for port 80
if [ "$EUID" -ne 0 ]; then
    echo "NOTE: Port 80 requires root privileges"
    echo "You may need to run with sudo or use a reverse proxy"
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

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FRONTEND_DIR="$SCRIPT_DIR/client-frontend"

cd $FRONTEND_DIR

# Check if Node.js is installed
echo ""
echo "=== Checking Node.js ==="

if ! command -v node &> /dev/null; then
    echo "Node.js is not installed!"
    echo ""
    echo "Please install Node.js (v18 or later) first:"
    echo "  Ubuntu/Debian: curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt-get install -y nodejs"
    echo "  CentOS/RHEL: curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash - && sudo yum install -y nodejs"
    exit 1
fi

NODE_VERSION=$(node --version)
echo "✓ Node.js detected: $NODE_VERSION"

# Create .env file
echo ""
echo "=== Creating Environment Configuration ==="

cat > .env <<EOF
VITE_CENTRAL_SERVER_URL=$CENTRAL_SERVER_URL
VITE_CLIENT_TOKEN=$CLIENT_TOKEN
VITE_CLIENT_ID=$CLIENT_ID
EOF

echo "✓ Configuration saved to .env"

# Install dependencies
echo ""
echo "=== Installing Dependencies ==="
echo "This may take a few minutes..."

npm install

echo "✓ Dependencies installed"

# Build production version
echo ""
echo "=== Building Production Build ==="

npm run build

echo "✓ Production build complete"

# Create systemd service for production
echo ""
echo "=== Creating Systemd Service ==="

sudo bash -c "cat > /etc/systemd/system/client-frontend.service" <<EOF
[Unit]
Description=Client Frontend for Spot Optimizer
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$FRONTEND_DIR
ExecStart=$(which npm) run preview
Restart=always
RestartSec=10
StandardOutput=append:/var/log/client-frontend.log
StandardError=append:/var/log/client-frontend.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable client-frontend.service

echo "✓ Systemd service created and enabled"

# Create helper scripts
echo ""
echo "=== Creating Helper Scripts ==="

# Status script
sudo bash -c "cat > /usr/local/bin/client-frontend-status" <<'EOF'
#!/bin/bash
systemctl status client-frontend.service
EOF
sudo chmod +x /usr/local/bin/client-frontend-status

# Logs script
sudo bash -c "cat > /usr/local/bin/client-frontend-logs" <<'EOF'
#!/bin/bash
tail -f /var/log/client-frontend.log
EOF
sudo chmod +x /usr/local/bin/client-frontend-logs

# Restart script
sudo bash -c "cat > /usr/local/bin/client-frontend-restart" <<'EOF'
#!/bin/bash
sudo systemctl restart client-frontend.service
echo "Client frontend restarted"
EOF
sudo chmod +x /usr/local/bin/client-frontend-restart

echo "✓ Helper scripts created:"
echo "  - client-frontend-status"
echo "  - client-frontend-logs"
echo "  - client-frontend-restart"

# Start service
echo ""
echo "=== Starting Client Frontend ==="

sudo systemctl start client-frontend.service

sleep 3

if sudo systemctl is-active --quiet client-frontend.service; then
    echo "✓ Client frontend is running"
else
    echo "✗ Client frontend failed to start"
    echo "Check logs with: client-frontend-logs"
    exit 1
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Summary
echo ""
echo "======================================================================="
echo "✓ Client Frontend Setup Complete!"
echo "======================================================================="
echo ""
echo "The client frontend is now running on port 80"
echo ""
echo "Access the dashboard at:"
echo "  http://$SERVER_IP"
echo "  http://localhost (if local)"
echo ""
echo "The frontend will:"
echo "  • Show client-specific information only"
echo "  • Auto-refresh data every 15 seconds"
echo "  • Display agents, instances, and savings"
echo ""
echo "Useful commands:"
echo "  client-frontend-status   - Check frontend status"
echo "  client-frontend-logs     - View live logs"
echo "  client-frontend-restart  - Restart frontend"
echo ""
echo "To run in development mode:"
echo "  cd $FRONTEND_DIR"
echo "  sudo npm run dev"
echo ""
echo "======================================================================="
