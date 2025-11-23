#!/bin/bash
# ============================================================================
# AWS Spot Optimizer Agent - Uninstall Script
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${RED}[WARNING]${NC} $1"; }

echo ""
echo "============================================"
echo "  Spot Optimizer Agent Uninstaller"
echo "============================================"
echo ""

read -p "Are you sure you want to uninstall the Spot Optimizer Agent? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Uninstall cancelled"
    exit 0
fi

# Notify server before uninstall
log_info "Notifying server of agent removal..."
if [ -f /etc/spot-optimizer/agent.env ]; then
    # Load configuration
    source /etc/spot-optimizer/agent.env

    # Get instance ID from metadata
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")

    # Try to notify server (don't fail if server is unreachable)
    if [ -n "$SPOT_OPTIMIZER_SERVER_URL" ] && [ -n "$SPOT_OPTIMIZER_CLIENT_TOKEN" ]; then
        curl -s -X POST "${SPOT_OPTIMIZER_SERVER_URL}/api/agents/uninstall" \
            -H "Authorization: Bearer ${SPOT_OPTIMIZER_CLIENT_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"instance_id\": \"${INSTANCE_ID}\", \"reason\": \"manual_uninstall\"}" \
            --max-time 10 2>/dev/null || log_warn "Could not notify server (continuing anyway)"
    fi
else
    log_warn "Configuration not found, skipping server notification"
fi

# Stop and disable service
log_info "Stopping service..."
sudo systemctl stop spot-optimizer-agent 2>/dev/null || true
sudo systemctl disable spot-optimizer-agent 2>/dev/null || true

# Remove service file
log_info "Removing systemd service..."
sudo rm -f /etc/systemd/system/spot-optimizer-agent.service
sudo systemctl daemon-reload

# Remove directories
log_info "Removing agent files..."
sudo rm -rf /opt/spot-optimizer-agent
sudo rm -rf /etc/spot-optimizer
sudo rm -rf /var/log/spot-optimizer

# Remove helper scripts
log_info "Removing helper scripts..."
sudo rm -f /usr/local/bin/spot-agent-status
sudo rm -f /usr/local/bin/spot-agent-logs
sudo rm -f /usr/local/bin/spot-agent-restart

# Remove logrotate config
sudo rm -f /etc/logrotate.d/spot-optimizer

echo ""
log_success "Spot Optimizer Agent has been uninstalled"
echo ""
