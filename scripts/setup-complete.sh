#!/bin/bash

# ==============================================================================
# AWS Spot Optimizer - Complete Setup Script v3.0.0
# ==============================================================================
# Installs:
# - Spot Optimizer Agent (backend)
# - Client Dashboard (frontend)
# - Nginx reverse proxy (port 80)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. Run as a normal user with sudo privileges."
    exit 1
fi

clear
echo -e "${GREEN}"
cat << "EOF"
    ___        ______    ____              __     ____        __  _           _
   /   |      / ____/   / __ \____  ____  / /_   / __ \____  / /_(_)___ ___  (_)___  ___  _____
  / /| | __  / /   __  / / / / __ \/ __ \/ __/  / / / / __ \/ __/ / __ `__ \/ /_  / / _ \/ ___/
 / ___ |/ /_/ /__ / /_/ /_/ / /_/ / /_/ / /_   / /_/ / /_/ / /_/ / / / / / / / / /_/  __/ /
/_/  |_|\____/____/\____/____/ .___/\____/\__/   \____/ .___/\__/_/_/ /_/ /_/_/ /___/\___/_/
                            /_/                       /_/

              COMPLETE SETUP v3.0.0 - Agent + Dashboard + Nginx
EOF
echo -e "${NC}\n"

print_header "AWS Spot Optimizer - Complete Installation"

# ==============================================================================
# DETECT ENVIRONMENT
# ==============================================================================

print_header "Step 1: Environment Detection"

# Check if running on EC2
IS_EC2=false
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --connect-timeout 2 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    IS_EC2=true
    print_success "Running on EC2 instance (IMDSv2 detected)"

    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

    print_info "Instance ID: $INSTANCE_ID"
    print_info "Private IP: $PRIVATE_IP"
    [ -n "$PUBLIC_IP" ] && print_info "Public IP: $PUBLIC_IP"
else
    print_warning "Not running on EC2 - some features may be limited"
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
    PRIVATE_IP="127.0.0.1"
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    print_success "Detected OS: $NAME $VERSION_ID"
else
    print_error "Cannot detect OS"
    exit 1
fi

# ==============================================================================
# INSTANCE MEMORY - Check for previous installation
# ==============================================================================

INSTANCE_MEMORY_DIR="/var/lib/spot-optimizer"
INSTANCE_MEMORY_FILE="$INSTANCE_MEMORY_DIR/instance-config.env"

# Check if previous configuration exists
REUSE_CONFIG=false
if [ -f "$INSTANCE_MEMORY_FILE" ]; then
    print_info "Previous installation detected!"
    echo ""
    cat "$INSTANCE_MEMORY_FILE" | grep -v "^#" | grep "=" || true
    echo ""
    read -p "Would you like to reuse the previous configuration? (y/n): " REUSE_ANSWER

    if [[ "$REUSE_ANSWER" =~ ^[Yy]$ ]]; then
        REUSE_CONFIG=true
        print_success "Loading previous configuration..."
        source "$INSTANCE_MEMORY_FILE"

        # Override with saved values
        INSTALL_AGENT=${SAVED_INSTALL_AGENT:-false}
        INSTALL_DASHBOARD=${SAVED_INSTALL_DASHBOARD:-false}
        SERVER_URL=${SAVED_SERVER_URL:-}
        CLIENT_TOKEN=${SAVED_CLIENT_TOKEN:-}
        AWS_REGION=${SAVED_AWS_REGION:-ap-south-1}
        LOGICAL_AGENT_ID=${SAVED_LOGICAL_AGENT_ID:-}
        BACKEND_URL=${SAVED_BACKEND_URL:-}

        print_info "Previous configuration loaded successfully"
    fi
fi

# ==============================================================================
# USER INPUT
# ==============================================================================

print_header "Step 2: Configuration"

if [ "$REUSE_CONFIG" = false ]; then
    echo "What would you like to install?"
    echo "  1) Agent only (for client EC2 instances)"
    echo "  2) Dashboard only (for management server)"
    echo "  3) Both Agent and Dashboard"
    echo ""
    read -p "Enter choice [1-3]: " INSTALL_CHOICE

    case $INSTALL_CHOICE in
        1) INSTALL_AGENT=true; INSTALL_DASHBOARD=false ;;
        2) INSTALL_AGENT=false; INSTALL_DASHBOARD=true ;;
        3) INSTALL_AGENT=true; INSTALL_DASHBOARD=true ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
fi

if [ "$INSTALL_AGENT" = true ] && [ "$REUSE_CONFIG" = false ]; then
    echo ""
    read -p "Enter Central Server URL (e.g., http://10.0.1.50:5000): " SERVER_URL
    if [ -z "$SERVER_URL" ]; then
        print_error "Server URL is required for agent"
        exit 1
    fi
    SERVER_URL=${SERVER_URL%/}

    read -p "Enter Client Token: " CLIENT_TOKEN
    if [ -z "$CLIENT_TOKEN" ]; then
        print_error "Client token is required"
        exit 1
    fi

    # Validate token with backend
    print_info "Validating client token with server..."

    # Make request and capture response
    VALIDATION_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" \
        -H "Authorization: Bearer $CLIENT_TOKEN" \
        "${SERVER_URL}/api/client/validate" 2>/dev/null)

    # Extract HTTP code from the end
    HTTP_CODE=$(echo "$VALIDATION_RESPONSE" | grep -oP 'HTTP_CODE:\K[0-9]+' || echo "000")
    RESPONSE_BODY=$(echo "$VALIDATION_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

    if [ "$HTTP_CODE" = "200" ]; then
        # Try to extract client name (works with or without jq)
        if command -v jq &> /dev/null; then
            CLIENT_NAME=$(echo "$RESPONSE_BODY" | jq -r '.name // "Unknown"' 2>/dev/null)
        else
            CLIENT_NAME=$(echo "$RESPONSE_BODY" | grep -oP '"name"\s*:\s*"\K[^"]+' || echo "Validated")
        fi
        print_success "Token validated successfully! Client: $CLIENT_NAME"
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        print_error "Invalid client token! Please check your token and try again."
        print_error "Get your token from the admin dashboard at: $SERVER_URL"
        exit 1
    elif [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
        print_error "Cannot connect to server at: $SERVER_URL"
        print_error "Please check the server URL and ensure the server is running."
        exit 1
    else
        print_warning "Could not validate token (HTTP $HTTP_CODE). Proceeding anyway..."
    fi

    read -p "Enter AWS Region [ap-south-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-ap-south-1}

    read -p "Enter Logical Agent ID (optional, press Enter to use instance ID): " LOGICAL_AGENT_ID
fi

if [ "$INSTALL_DASHBOARD" = true ] && [ "$REUSE_CONFIG" = false ]; then
    echo ""
    # Default to SERVER_URL if agent is also being installed
    DEFAULT_BACKEND=${SERVER_URL:-http://localhost:5000}
    read -p "Enter Backend API URL [$DEFAULT_BACKEND]: " BACKEND_URL
    BACKEND_URL=${BACKEND_URL:-$DEFAULT_BACKEND}
    BACKEND_URL=${BACKEND_URL%/}
fi

# ==============================================================================
# SAVE INSTANCE MEMORY
# ==============================================================================

# Save configuration for future reinstalls (survives uninstall)
sudo mkdir -p "$INSTANCE_MEMORY_DIR"
sudo tee "$INSTANCE_MEMORY_FILE" > /dev/null << EOF
# Spot Optimizer Instance Memory
# This file is preserved during uninstall to remember instance configuration
# Generated: $(date)

SAVED_INSTALL_AGENT=$INSTALL_AGENT
SAVED_INSTALL_DASHBOARD=$INSTALL_DASHBOARD
SAVED_SERVER_URL=$SERVER_URL
SAVED_CLIENT_TOKEN=$CLIENT_TOKEN
SAVED_AWS_REGION=$AWS_REGION
SAVED_LOGICAL_AGENT_ID=$LOGICAL_AGENT_ID
SAVED_BACKEND_URL=$BACKEND_URL
SAVED_INSTANCE_ID=$INSTANCE_ID
EOF

sudo chmod 600 "$INSTANCE_MEMORY_FILE"
print_info "Configuration saved for future reinstalls"

echo ""
print_warning "Installation Summary:"
[ "$INSTALL_AGENT" = true ] && echo "  • Agent: YES (Server: $SERVER_URL)"
[ "$INSTALL_DASHBOARD" = true ] && echo "  • Dashboard: YES (Backend: $BACKEND_URL)"
echo ""
read -p "Continue with installation? (y/yes): " CONFIRM

# Accept y, Y, yes, Yes, YES
if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    print_error "Installation cancelled."
    exit 0
fi

# ==============================================================================
# INSTALL DEPENDENCIES
# ==============================================================================

print_header "Step 3: Installing Dependencies"

print_info "Updating package lists..."

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt-get update -qq
    sudo apt-get install -y python3 python3-pip python3-venv curl jq unzip nginx
elif [ "$OS" = "amzn" ] || [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
    sudo yum update -y -q
    sudo yum install -y python3 python3-pip curl jq unzip nginx
else
    print_error "Unsupported OS: $OS"
    exit 1
fi

# Install AWS CLI if not present and on EC2
if [ "$IS_EC2" = true ] && ! command -v aws &> /dev/null; then
    print_info "Installing AWS CLI v2..."
    cd /tmp
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install > /dev/null 2>&1
    rm -rf aws awscliv2.zip
    cd - > /dev/null
fi

print_success "Dependencies installed"
print_success "Python: $(python3 --version)"
print_success "Nginx: $(nginx -v 2>&1 | cut -d'/' -f2)"

# ==============================================================================
# INSTALL AGENT
# ==============================================================================

if [ "$INSTALL_AGENT" = true ]; then
    print_header "Step 4: Installing Spot Optimizer Agent"

    APP_DIR="/opt/spot-optimizer-agent"
    LOG_DIR="/var/log/spot-optimizer"
    CONFIG_DIR="/etc/spot-optimizer"

    # Create directories
    sudo mkdir -p $APP_DIR $LOG_DIR $CONFIG_DIR
    sudo chown $USER:$USER $APP_DIR $LOG_DIR $CONFIG_DIR

    # Create Python virtual environment
    print_info "Creating Python virtual environment..."
    python3 -m venv $APP_DIR/venv
    source $APP_DIR/venv/bin/activate

    # Install Python dependencies
    cat > $APP_DIR/requirements.txt << 'EOF'
boto3>=1.34.0
requests>=2.31.0
python-dotenv>=1.0.0
urllib3>=2.0.0
EOF

    pip install --quiet --upgrade pip
    pip install --quiet -r $APP_DIR/requirements.txt
    print_success "Python dependencies installed"

    # Copy agent script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    AGENT_FILE="$SCRIPT_DIR/../backend/spot_optimizer_agent.py"

    if [ -f "$AGENT_FILE" ]; then
        cp "$AGENT_FILE" $APP_DIR/spot_agent.py
        print_success "Agent script installed from $AGENT_FILE"
    elif [ -f "/tmp/spot_optimizer_agent.py" ]; then
        cp /tmp/spot_optimizer_agent.py $APP_DIR/spot_agent.py
        print_success "Agent script installed from /tmp/"
    else
        print_error "Agent script not found"
        print_info "Please ensure spot_optimizer_agent.py is in ../backend/ or /tmp/"
        exit 1
    fi

    # Create configuration
    cat > $CONFIG_DIR/agent.env << EOF
# AWS Spot Optimizer Agent Configuration
SPOT_OPTIMIZER_SERVER_URL=$SERVER_URL
SPOT_OPTIMIZER_CLIENT_TOKEN=$CLIENT_TOKEN
AWS_REGION=$AWS_REGION
LOGICAL_AGENT_ID=$LOGICAL_AGENT_ID

# Timing Configuration
HEARTBEAT_INTERVAL=30
PENDING_COMMANDS_CHECK_INTERVAL=15
CONFIG_REFRESH_INTERVAL=60
PRICING_REPORT_INTERVAL=300
TERMINATION_CHECK_INTERVAL=5
REBALANCE_CHECK_INTERVAL=30
CLEANUP_INTERVAL=3600

# Switch Configuration
AUTO_TERMINATE_OLD_INSTANCE=true
TERMINATE_WAIT_TIME=300
CREATE_SNAPSHOT_ON_SWITCH=true

# Cleanup Configuration
CLEANUP_SNAPSHOTS_OLDER_THAN_DAYS=7
CLEANUP_AMIS_OLDER_THAN_DAYS=30
EOF

    chmod 600 $CONFIG_DIR/agent.env
    print_success "Agent configuration created"

    # Create systemd service
    sudo tee /etc/systemd/system/spot-optimizer-agent.service > /dev/null << EOF
[Unit]
Description=AWS Spot Optimizer Agent v4.0.0
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$CONFIG_DIR/agent.env
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/spot_agent.py
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/agent.log
StandardError=append:$LOG_DIR/agent-error.log

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable spot-optimizer-agent > /dev/null 2>&1
    print_success "Agent systemd service created"

    deactivate
fi

# ==============================================================================
# INSTALL DASHBOARD (React Frontend)
# ==============================================================================

if [ "$INSTALL_DASHBOARD" = true ]; then
    print_header "Step 5: Installing Client Dashboard (React)"

    DASHBOARD_DIR="/var/www/spot-optimizer-dashboard"

    # Create directory
    sudo mkdir -p $DASHBOARD_DIR
    sudo chown $USER:$USER $DASHBOARD_DIR

    # Install Node.js if not present
    if ! command -v node &> /dev/null; then
        print_info "Installing Node.js..."
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif [ "$OS" = "amzn" ] || [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            sudo yum install -y nodejs
        fi
        print_success "Node.js installed"
    else
        print_success "Node.js already installed ($(node --version))"
    fi

    # Copy React frontend source
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    FRONTEND_SRC="$SCRIPT_DIR/../frontend-react"
    API_SRC="$SCRIPT_DIR/../frontend/api_server.py"

    if [ ! -d "$FRONTEND_SRC" ]; then
        print_error "React frontend directory not found at $FRONTEND_SRC"
        exit 1
    fi

    # Copy source and build
    print_info "Building React dashboard..."
    cp -r "$FRONTEND_SRC"/* $DASHBOARD_DIR/
    cd $DASHBOARD_DIR

    # Install dependencies and build
    npm install --quiet
    npm run build
    print_success "React dashboard built successfully"

    # Setup API server
    print_info "Setting up API server..."
    API_DIR="/opt/spot-optimizer-api"
    sudo mkdir -p $API_DIR
    sudo chown $USER:$USER $API_DIR

    # Copy API server
    if [ -f "$API_SRC" ]; then
        cp "$API_SRC" $API_DIR/api_server.py
    else
        print_error "API server not found at $API_SRC"
        exit 1
    fi

    # Create Python virtual environment for API
    python3 -m venv $API_DIR/venv
    source $API_DIR/venv/bin/activate

    # Install API dependencies
    pip install --quiet flask flask-cors requests
    print_success "API server dependencies installed"

    # Read client token from agent config if it exists
    if [ -f /etc/spot-optimizer/agent.env ]; then
        source /etc/spot-optimizer/agent.env
    fi

    # Create systemd service for API
    sudo tee /etc/systemd/system/spot-optimizer-api.service > /dev/null << EOF
[Unit]
Description=Spot Optimizer API Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$API_DIR
Environment="BACKEND_URL=$BACKEND_URL"
Environment="CLIENT_TOKEN=${SPOT_OPTIMIZER_CLIENT_TOKEN:-}"
Environment="PORT=5000"
ExecStart=$API_DIR/venv/bin/python api_server.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/spot-optimizer/api.log
StandardError=append:/var/log/spot-optimizer/api-error.log

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable spot-optimizer-api > /dev/null 2>&1
    sudo systemctl start spot-optimizer-api
    print_success "API server configured and started"

    deactivate

    # ==============================================================================
    # CONFIGURE NGINX
    # ==============================================================================

    print_header "Step 6: Configuring Nginx (Port 80)"

    # Create nginx configuration for React SPA + API proxy
    sudo tee /etc/nginx/sites-available/spot-optimizer-dashboard > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    # Serve React build
    root /var/www/spot-optimizer-dashboard/dist;
    index index.html;

    # API proxy to Flask backend
    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    # Serve static files
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # SPA fallback - serve index.html for all routes
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

    # Enable the site
    sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    sudo ln -sf /etc/nginx/sites-available/spot-optimizer-dashboard /etc/nginx/sites-enabled/

    # Test nginx configuration
    if sudo nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration valid"
    else
        print_error "Nginx configuration error"
        sudo nginx -t
        exit 1
    fi

    sudo systemctl enable nginx > /dev/null 2>&1
    print_success "Nginx configured on port 80"
fi

# ==============================================================================
# CREATE HELPER SCRIPTS
# ==============================================================================

print_header "Step 7: Creating Helper Scripts"

# Status script
sudo tee /usr/local/bin/spot-optimizer-status > /dev/null << 'EOF'
#!/bin/bash
echo "═══════════════════════════════════════════════════════════════"
echo "  AWS Spot Optimizer Status"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Agent status
if systemctl is-active --quiet spot-optimizer-agent 2>/dev/null; then
    echo -e "Agent Service:     \033[0;32m● Running\033[0m"
else
    echo -e "Agent Service:     \033[0;31m○ Stopped\033[0m"
fi

# API Server status
if systemctl is-active --quiet spot-optimizer-api 2>/dev/null; then
    echo -e "API Service:       \033[0;32m● Running\033[0m"
else
    echo -e "API Service:       \033[0;31m○ Stopped\033[0m"
fi

# Nginx status
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "Nginx Service:     \033[0;32m● Running\033[0m"
else
    echo -e "Nginx Service:     \033[0;31m○ Stopped\033[0m"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Show recent agent logs if running
if [ -f /var/log/spot-optimizer/agent.log ]; then
    echo "Recent Agent Logs:"
    echo "─────────────────────────────────────────────────────────────"
    tail -10 /var/log/spot-optimizer/agent.log
fi
EOF
sudo chmod +x /usr/local/bin/spot-optimizer-status
print_success "Created: spot-optimizer-status"

# Restart all script
sudo tee /usr/local/bin/spot-optimizer-restart > /dev/null << 'EOF'
#!/bin/bash
echo "Restarting Spot Optimizer services..."
sudo systemctl restart spot-optimizer-agent 2>/dev/null || true
sudo systemctl restart spot-optimizer-api 2>/dev/null || true
sudo systemctl restart nginx 2>/dev/null || true
sleep 2
spot-optimizer-status
EOF
sudo chmod +x /usr/local/bin/spot-optimizer-restart
print_success "Created: spot-optimizer-restart"

# Logs script
sudo tee /usr/local/bin/spot-optimizer-logs > /dev/null << 'EOF'
#!/bin/bash
echo "Tailing all logs (Ctrl+C to stop)..."
echo "═══════════════════════════════════════════════════════════════"
tail -f /var/log/spot-optimizer/*.log 2>/dev/null
EOF
sudo chmod +x /usr/local/bin/spot-optimizer-logs
print_success "Created: spot-optimizer-logs"

# ==============================================================================
# SETUP LOG ROTATION
# ==============================================================================

print_header "Step 8: Configuring Log Rotation"

sudo tee /etc/logrotate.d/spot-optimizer > /dev/null << EOF
/var/log/spot-optimizer/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $USER $USER
    sharedscripts
    postrotate
        systemctl reload spot-optimizer-agent > /dev/null 2>&1 || true
        systemctl reload spot-optimizer-api > /dev/null 2>&1 || true
    endscript
}
EOF

print_success "Log rotation configured"

# ==============================================================================
# START SERVICES
# ==============================================================================

print_header "Step 9: Starting Services"

if [ "$INSTALL_AGENT" = true ]; then
    print_info "Starting agent service..."
    sudo systemctl start spot-optimizer-agent
    sleep 2
    if sudo systemctl is-active --quiet spot-optimizer-agent; then
        print_success "Agent service started"
    else
        print_error "Agent service failed to start"
        print_info "Check logs: tail -50 /var/log/spot-optimizer/agent.log"
    fi
fi

if [ "$INSTALL_DASHBOARD" = true ]; then
    print_info "Starting nginx..."
    sudo systemctl restart nginx
    if sudo systemctl is-active --quiet nginx; then
        print_success "Nginx started"
    else
        print_error "Nginx failed to start"
    fi

    # Verify API server is running
    if sudo systemctl is-active --quiet spot-optimizer-api; then
        print_success "API server is running"
    else
        print_warning "API server is not running"
        print_info "Check logs: tail -50 /var/log/spot-optimizer/api.log"
    fi
fi

# ==============================================================================
# INSTALLATION COMPLETE
# ==============================================================================

print_header "Installation Complete!"

echo ""
print_success "AWS Spot Optimizer has been installed!"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$INSTALL_AGENT" = true ]; then
    print_info "Agent Installation:"
    echo "  • Application: /opt/spot-optimizer-agent"
    echo "  • Configuration: /etc/spot-optimizer/agent.env"
    echo "  • Logs: /var/log/spot-optimizer/"
    echo ""
fi

if [ "$INSTALL_DASHBOARD" = true ]; then
    print_info "Dashboard Installation:"
    echo "  • Frontend: /var/www/spot-optimizer-dashboard"
    echo "  • API Server: /opt/spot-optimizer-api"
    echo "  • Logs: /var/log/spot-optimizer/"
    echo ""

    DASHBOARD_URL="http://${PUBLIC_IP:-localhost}"
    print_info "Dashboard URL: ${BLUE}${DASHBOARD_URL}${NC}"
    echo ""
fi

print_info "Helper Commands:"
echo -e "  • ${BLUE}spot-optimizer-status${NC}  - Check all services"
echo -e "  • ${BLUE}spot-optimizer-restart${NC} - Restart all services"
echo -e "  • ${BLUE}spot-optimizer-logs${NC}    - View live logs"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Show current status
spot-optimizer-status

exit 0
