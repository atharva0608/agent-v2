#!/bin/bash

# ==============================================================================
# AWS Spot Optimizer - Production Agent Installation Script v2.0.0 FINAL
# ==============================================================================
# ✓ 100% Backend Compatible
# ✓ Full Switching Capabilities
# ✓ Production Ready
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}================================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

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

                    PRODUCTION AGENT v2.0.0 FINAL
                    100% Backend Compatible
EOF
echo -e "${NC}\n"

print_header "AWS Spot Optimizer - Production Agent Installation"

# EC2 Check
print_header "Pre-flight Check: EC2 Environment"

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --connect-timeout 2 2>/dev/null)

if [ -z "$TOKEN" ]; then
    print_error "NOT running on EC2 - This agent requires EC2"
    exit 1
fi

print_success "Running on EC2 instance (IMDSv2 detected)"

# User Input
print_info "This script will install the Production Spot Optimizer Agent."
echo ""

while true; do
    read -p "Enter Central Server URL (e.g., http://10.0.1.50:5000): " SERVER_URL
    if [[ $SERVER_URL =~ ^https?:// ]]; then
        SERVER_URL=${SERVER_URL%/}
        break
    else
        print_error "Invalid URL format. Please include http:// or https://"
    fi
done

read -p "Enter Client Token: " CLIENT_TOKEN
if [ -z "$CLIENT_TOKEN" ]; then
    print_error "Client token cannot be empty"
    exit 1
fi

read -p "Enter AWS Region [ap-south-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-south-1}

echo ""
print_warning "Installation Summary:"
echo "  Server URL: $SERVER_URL"
echo "  Client Token: ${CLIENT_TOKEN:0:10}..."
echo "  AWS Region: $AWS_REGION"
echo ""
read -p "Continue with installation? (yes/no): " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy][Ee][Ss]$ ]]; then
    print_error "Installation cancelled."
    exit 0
fi

# System Detection
print_header "Step 1: System Detection"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VERSION=$VERSION_ID
    print_success "Detected OS: $OS $VERSION"
else
    print_error "Cannot detect OS."
    exit 1
fi

# Install Dependencies
print_header "Step 2: Installing Dependencies"

print_info "Updating package lists..."

if command -v apt-get &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y python3 python3-pip python3-venv curl jq unzip
    
    if ! command -v aws &> /dev/null; then
        print_info "Installing AWS CLI v2..."
        cd /tmp
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        sudo ./aws/install > /dev/null 2>&1
        rm -rf aws awscliv2.zip
        cd - > /dev/null
    fi
fi

print_success "Python 3 installed: $(python3 --version)"
print_success "AWS CLI installed: $(aws --version 2>&1 | cut -d' ' -f1)"

# Create Directories
print_header "Step 3: Creating Directory Structure"

APP_DIR="/opt/spot-optimizer-agent"
LOG_DIR="/var/log/spot-optimizer"
CONFIG_DIR="/etc/spot-optimizer"

sudo mkdir -p $APP_DIR
sudo chown $USER:$USER $APP_DIR
print_success "Created application directory: $APP_DIR"

sudo mkdir -p $LOG_DIR
sudo chown $USER:$USER $LOG_DIR
touch $LOG_DIR/agent.log
touch $LOG_DIR/agent-error.log
chmod 644 $LOG_DIR/agent.log
chmod 644 $LOG_DIR/agent-error.log
print_success "Created log directory: $LOG_DIR"

sudo mkdir -p $CONFIG_DIR
sudo chown $USER:$USER $CONFIG_DIR
print_success "Created config directory: $CONFIG_DIR"

# Install Python Dependencies
print_header "Step 4: Installing Python Dependencies"

cd $APP_DIR

print_info "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

cat > requirements.txt << 'EOF'
boto3>=1.34.0
requests>=2.31.0
python-dotenv>=1.0.0
urllib3>=2.0.0
EOF

print_info "Installing Python packages..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
print_success "Python dependencies installed"

# Copy Agent Script
print_header "Step 5: Installing Production Agent Script"

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

# Create Configuration
print_header "Step 6: Creating Configuration"

cat > $CONFIG_DIR/agent.env << EOF
# AWS Spot Optimizer Agent Configuration
CENTRAL_SERVER_URL=$SERVER_URL
CLIENT_TOKEN=$CLIENT_TOKEN
AWS_REGION=$AWS_REGION
EOF

chmod 600 $CONFIG_DIR/agent.env
print_success "Configuration file created: $CONFIG_DIR/agent.env"

# Create Systemd Service
print_header "Step 7: Creating Systemd Service"

sudo tee /etc/systemd/system/spot-optimizer-agent.service > /dev/null << EOF
[Unit]
Description=AWS Spot Optimizer Production Agent v2.0.0
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

print_success "Systemd service created"

# Check IAM Permissions
print_header "Step 8: Checking IAM Permissions"

print_info "Verifying AWS IAM permissions..."

if aws sts get-caller-identity --region $AWS_REGION > /dev/null 2>&1; then
    print_success "AWS credentials: OK"
else
    print_error "AWS credentials: FAILED"
    print_warning "The agent requires proper IAM role permissions"
fi

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
if aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION > /dev/null 2>&1; then
    print_success "EC2 API access: OK"
else
    print_warning "EC2 API access: LIMITED"
fi

print_info "Required IAM Permissions:"
cat << 'POLICY_EOF'

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeSpotPriceHistory",
        "ec2:CreateImage",
        "ec2:CreateSnapshot",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:DescribeImages",
        "pricing:GetProducts"
      ],
      "Resource": "*"
    }
  ]
}
POLICY_EOF

# Test Connection
print_header "Step 9: Testing Connection to Central Server"

print_info "Testing connection to $SERVER_URL..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$SERVER_URL/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Successfully connected to central server"
else
    print_error "Cannot connect to central server (HTTP $HTTP_CODE)"
    exit 1
fi

# Start Service
print_header "Step 10: Starting Agent Service"

sudo systemctl daemon-reload
print_success "Systemd daemon reloaded"

sudo systemctl enable spot-optimizer-agent > /dev/null 2>&1
print_success "Service enabled to start on boot"

print_info "Starting agent service..."
sudo systemctl start spot-optimizer-agent

sleep 5

if sudo systemctl is-active --quiet spot-optimizer-agent; then
    print_success "Agent service is running"
    
    sleep 3
    
    if grep -q "Agent initialized successfully" $LOG_DIR/agent.log 2>/dev/null; then
        print_success "Agent initialized and connected to server"
    else
        print_warning "Agent started but initialization status unknown"
    fi
else
    print_error "Agent service failed to start"
    echo ""
    print_info "Last 20 lines of agent.log:"
    tail -n 20 $LOG_DIR/agent.log
    exit 1
fi

# Create Helper Scripts
print_header "Step 11: Creating Helper Scripts"

sudo tee /usr/local/bin/spot-agent-status > /dev/null << 'EOF'
#!/bin/bash
echo "=== Spot Optimizer Agent Status ==="
sudo systemctl status spot-optimizer-agent --no-pager
echo ""
echo "=== Recent Logs (last 30 lines) ==="
sudo tail -n 30 /var/log/spot-optimizer/agent.log
EOF
sudo chmod +x /usr/local/bin/spot-agent-status
print_success "Created: spot-agent-status"

sudo tee /usr/local/bin/spot-agent-logs > /dev/null << 'EOF'
#!/bin/bash
echo "Tailing agent logs (Ctrl+C to stop)..."
sudo tail -f /var/log/spot-optimizer/agent.log
EOF
sudo chmod +x /usr/local/bin/spot-agent-logs
print_success "Created: spot-agent-logs"

sudo tee /usr/local/bin/spot-agent-restart > /dev/null << 'EOF'
#!/bin/bash
echo "Restarting Spot Optimizer Agent..."
sudo systemctl restart spot-optimizer-agent
sleep 3
sudo systemctl status spot-optimizer-agent --no-pager
EOF
sudo chmod +x /usr/local/bin/spot-agent-restart
print_success "Created: spot-agent-restart"

# Setup Log Rotation
print_header "Step 12: Configuring Log Rotation"

sudo tee /etc/logrotate.d/spot-optimizer-agent > /dev/null << EOF
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
    endscript
}
EOF

print_success "Log rotation configured"

# Installation Complete
print_header "Installation Complete!"

echo ""
print_success "AWS Spot Optimizer Production Agent v2.0.0 has been installed!"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "Installation Summary:"
echo "  • Application: $APP_DIR"
echo "  • Configuration: $CONFIG_DIR/agent.env"
echo "  • Logs: $LOG_DIR"
echo "  • Service: spot-optimizer-agent.service"
echo ""
print_info "Features:"
echo "  ✓ Full instance switching (spot ↔ on-demand)"
echo "  ✓ AMI-based instance replacement"
echo "  ✓ Automatic old instance termination"
echo "  ✓ Real-time instance type detection"
echo "  ✓ Network configuration preservation"
echo "  ✓ 100% Backend compatible"
echo ""
print_info "Quick Commands:"
echo "  • ${BLUE}spot-agent-status${NC}   - Check agent status"
echo "  • ${BLUE}spot-agent-logs${NC}     - View live logs"
echo "  • ${BLUE}spot-agent-restart${NC}  - Restart agent"
echo ""
print_info "Next Steps:"
echo "  1. Verify agent is registered in dashboard"
echo "  2. Check instance appears in instance list"
echo "  3. Test manual switch from dashboard"
echo "  4. Monitor switch execution: ${BLUE}spot-agent-logs${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Show current status
print_header "Current Agent Status"

echo "Instance Details:"
INST_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
INST_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)
echo "  • Instance ID: $INST_ID"
echo "  • Instance Type: $INST_TYPE"
echo "  • Region: $AWS_REGION"
echo ""
echo "Agent Service:"
if sudo systemctl is-active --quiet spot-optimizer-agent; then
    echo "  • Status: ${GREEN}Running${NC}"
else
    echo "  • Status: ${RED}Stopped${NC}"
fi
echo ""

print_success "Installation complete! The agent is now running and ready."
echo ""
print_info "View live logs: ${BLUE}spot-agent-logs${NC}"
echo ""

exit 0
