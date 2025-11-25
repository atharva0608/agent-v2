#!/bin/bash
# ============================================================================
# AWS Spot Optimizer - Complete Uninstall Script
# ============================================================================
# This script completely removes ALL Spot Optimizer components from instance
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for confirmation flag
CONFIRMED=false
if [[ "$1" == "--yes" ]] || [[ "$1" == "-y" ]]; then
    CONFIRMED=true
fi

clear
echo -e "${RED}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     AWS SPOT OPTIMIZER - COMPLETE UNINSTALL                  ║
║                                                              ║
║     This will REMOVE ALL Spot Optimizer components          ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$CONFIRMED" = false ]; then
    echo ""
    log_warn "This script will remove:"
    echo "  • Spot Optimizer Agent service"
    echo "  • Dashboard and API service"
    echo "  • Nginx configuration (if installed by Spot Optimizer)"
    echo "  • All configuration files"
    echo "  • All log files"
    echo "  • All helper scripts"
    echo "  • All application directories"
    echo ""
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        log_info "Uninstall cancelled."
        exit 0
    fi
fi

echo ""
log_info "Starting complete uninstall..."
echo ""

# ============================================================================
# NOTIFY SERVER
# ============================================================================

log_info "Step 1: Notifying server of agent removal..."

if [ -f /etc/spot-optimizer/agent.env ]; then
    # Load configuration
    source /etc/spot-optimizer/agent.env

    # Get instance ID from metadata
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")

    # Try to notify server (don't fail if server is unreachable)
    if [ -n "$SPOT_OPTIMIZER_SERVER_URL" ] && [ -n "$SPOT_OPTIMIZER_CLIENT_TOKEN" ]; then
        if curl -s -X POST "${SPOT_OPTIMIZER_SERVER_URL}/api/agents/uninstall" \
            -H "Authorization: Bearer ${SPOT_OPTIMIZER_CLIENT_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"instance_id\": \"${INSTANCE_ID}\", \"reason\": \"manual_uninstall\"}" \
            --max-time 10 2>/dev/null; then
            log_success "Server notified successfully"
        else
            log_warn "Could not notify server (continuing anyway)"
        fi
    fi
else
    log_warn "Configuration not found, skipping server notification"
fi

# ============================================================================
# STOP SERVICES
# ============================================================================

log_info "Step 2: Stopping services..."

# Stop and disable agent service
if systemctl is-active --quiet spot-optimizer-agent 2>/dev/null; then
    log_info "  Stopping spot-optimizer-agent..."
    sudo systemctl stop spot-optimizer-agent 2>/dev/null || true
fi
if systemctl is-enabled --quiet spot-optimizer-agent 2>/dev/null; then
    sudo systemctl disable spot-optimizer-agent 2>/dev/null || true
fi

# Stop and disable API service
if systemctl is-active --quiet spot-optimizer-api 2>/dev/null; then
    log_info "  Stopping spot-optimizer-api..."
    sudo systemctl stop spot-optimizer-api 2>/dev/null || true
fi
if systemctl is-enabled --quiet spot-optimizer-api 2>/dev/null; then
    sudo systemctl disable spot-optimizer-api 2>/dev/null || true
fi

log_success "All services stopped"

# ============================================================================
# REMOVE SYSTEMD SERVICE FILES
# ============================================================================

log_info "Step 3: Removing systemd service files..."

if [ -f /etc/systemd/system/spot-optimizer-agent.service ]; then
    sudo rm -f /etc/systemd/system/spot-optimizer-agent.service
    log_info "  Removed spot-optimizer-agent.service"
fi

if [ -f /etc/systemd/system/spot-optimizer-api.service ]; then
    sudo rm -f /etc/systemd/system/spot-optimizer-api.service
    log_info "  Removed spot-optimizer-api.service"
fi

# Reload systemd
sudo systemctl daemon-reload
log_success "Systemd service files removed"

# ============================================================================
# REMOVE APPLICATION DIRECTORIES
# ============================================================================

log_info "Step 4: Removing application directories..."

if [ -d /opt/spot-optimizer-agent ]; then
    sudo rm -rf /opt/spot-optimizer-agent
    log_info "  Removed /opt/spot-optimizer-agent"
fi

if [ -d /opt/spot-optimizer-api ]; then
    sudo rm -rf /opt/spot-optimizer-api
    log_info "  Removed /opt/spot-optimizer-api"
fi

if [ -d /var/www/spot-optimizer-dashboard ]; then
    sudo rm -rf /var/www/spot-optimizer-dashboard
    log_info "  Removed /var/www/spot-optimizer-dashboard"
fi

log_success "Application directories removed"

# ============================================================================
# REMOVE CONFIGURATION FILES
# ============================================================================

log_info "Step 5: Removing configuration files..."

if [ -d /etc/spot-optimizer ]; then
    sudo rm -rf /etc/spot-optimizer
    log_info "  Removed /etc/spot-optimizer"
fi

# NOTE: /var/lib/spot-optimizer is PRESERVED for reinstallation memory
log_info "  Preserved /var/lib/spot-optimizer (instance memory)"

log_success "Configuration files removed"

# ============================================================================
# REMOVE LOG FILES
# ============================================================================

log_info "Step 6: Removing log files..."

if [ -d /var/log/spot-optimizer ]; then
    sudo rm -rf /var/log/spot-optimizer
    log_info "  Removed /var/log/spot-optimizer"
fi

log_success "Log files removed"

# ============================================================================
# REMOVE NGINX CONFIGURATION
# ============================================================================

log_info "Step 7: Removing Nginx configuration..."

if [ -f /etc/nginx/sites-enabled/spot-optimizer-dashboard ]; then
    sudo rm -f /etc/nginx/sites-enabled/spot-optimizer-dashboard
    log_info "  Removed /etc/nginx/sites-enabled/spot-optimizer-dashboard"
fi

if [ -f /etc/nginx/sites-available/spot-optimizer-dashboard ]; then
    sudo rm -f /etc/nginx/sites-available/spot-optimizer-dashboard
    log_info "  Removed /etc/nginx/sites-available/spot-optimizer-dashboard"
fi

# Restore default nginx site if needed
if [ ! -f /etc/nginx/sites-enabled/default ] && [ -f /etc/nginx/sites-available/default ]; then
    sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    log_info "  Restored default nginx site"
fi

# Test and reload nginx
if command -v nginx &> /dev/null; then
    if sudo nginx -t > /dev/null 2>&1; then
        sudo systemctl reload nginx 2>/dev/null || true
        log_success "Nginx configuration removed and reloaded"
    else
        log_warn "Nginx configuration test failed - you may need to fix nginx manually"
    fi
fi

# ============================================================================
# REMOVE HELPER SCRIPTS
# ============================================================================

log_info "Step 8: Removing helper scripts..."

# Old helper script names (from older versions)
sudo rm -f /usr/local/bin/spot-agent-status 2>/dev/null || true
sudo rm -f /usr/local/bin/spot-agent-logs 2>/dev/null || true
sudo rm -f /usr/local/bin/spot-agent-restart 2>/dev/null || true

# New helper script names
if [ -f /usr/local/bin/spot-optimizer-status ]; then
    sudo rm -f /usr/local/bin/spot-optimizer-status
    log_info "  Removed spot-optimizer-status"
fi

if [ -f /usr/local/bin/spot-optimizer-restart ]; then
    sudo rm -f /usr/local/bin/spot-optimizer-restart
    log_info "  Removed spot-optimizer-restart"
fi

if [ -f /usr/local/bin/spot-optimizer-logs ]; then
    sudo rm -f /usr/local/bin/spot-optimizer-logs
    log_info "  Removed spot-optimizer-logs"
fi

log_success "Helper scripts removed"

# ============================================================================
# REMOVE LOG ROTATION CONFIGURATION
# ============================================================================

log_info "Step 9: Removing log rotation configuration..."

if [ -f /etc/logrotate.d/spot-optimizer ]; then
    sudo rm -f /etc/logrotate.d/spot-optimizer
    log_info "  Removed /etc/logrotate.d/spot-optimizer"
fi

log_success "Log rotation configuration removed"

# ============================================================================
# CLEANUP TEMPORARY FILES
# ============================================================================

log_info "Step 10: Cleaning up temporary files..."

# Remove any temporary files in /tmp
sudo rm -rf /tmp/spot-optimizer* 2>/dev/null || true
sudo rm -f /tmp/spot_optimizer_agent.py 2>/dev/null || true

log_success "Temporary files cleaned up"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  Uninstall Complete                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_success "Spot Optimizer has been completely removed from this instance!"
echo ""
log_info "Summary of removed components:"
echo "  ✓ Agent service (spot-optimizer-agent)"
echo "  ✓ API server service (spot-optimizer-api)"
echo "  ✓ Dashboard application (/var/www/spot-optimizer-dashboard)"
echo "  ✓ Agent application (/opt/spot-optimizer-agent)"
echo "  ✓ API server application (/opt/spot-optimizer-api)"
echo "  ✓ Configuration files (/etc/spot-optimizer)"
echo "  ✓ Log files (/var/log/spot-optimizer)"
echo "  ✓ Nginx configuration"
echo "  ✓ Helper scripts (status, restart, logs)"
echo "  ✓ Log rotation configuration"
echo "  ✓ Temporary files"
echo ""
log_info "System packages (Python, Node.js, Nginx, etc.) were NOT removed"
log_info "To remove them, run:"
echo "  • Ubuntu/Debian: sudo apt remove python3-venv nodejs nginx"
echo "  • Amazon Linux/RHEL: sudo yum remove python3 nodejs nginx"
echo ""
log_warn "Important notes:"
echo "  • This instance is no longer reporting to the Spot Optimizer backend"
echo "  • You may need to remove this instance from the admin dashboard manually"
echo "  • Any EC2 replicas created by this agent will NOT be automatically terminated"
echo "  • Instance memory preserved at /var/lib/spot-optimizer for future reinstalls"
echo "  • To completely remove including memory: sudo rm -rf /var/lib/spot-optimizer"
echo ""
