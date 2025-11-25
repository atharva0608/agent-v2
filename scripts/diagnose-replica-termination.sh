#!/bin/bash
# Diagnostic script for replica termination connectivity issues
# Tests all API endpoints needed for replica termination worker

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════════════"
echo "  Replica Termination Connectivity Diagnostic"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Load agent configuration
if [ -f /opt/spot-optimizer-agent/.instance-memory ]; then
    AGENT_ID=$(grep -oP '"agent_id"\s*:\s*"\K[^"]+' /opt/spot-optimizer-agent/.instance-memory 2>/dev/null || echo "")
    echo "Agent ID: ${AGENT_ID:-Not found}"
fi

# Get environment variables
CLIENT_TOKEN="${SPOT_OPTIMIZER_CLIENT_TOKEN:-token-NEfxI26u2o9lEQgX8llBHxegz5JdrwRP}"
SERVER_URL="${SPOT_OPTIMIZER_SERVER_URL:-http://localhost:5000}"

echo "Server URL: $SERVER_URL"
echo "Client Token: ${CLIENT_TOKEN:0:15}..."
echo ""

# Test 1: Local API Proxy
echo -e "${YELLOW}[TEST 1]${NC} Testing Local API Proxy (localhost:5000)..."
if curl -s --connect-timeout 3 http://localhost:5000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Local API proxy is responding"
    HEALTH=$(curl -s http://localhost:5000/health)
    echo "   Response: $HEALTH"
else
    echo -e "${RED}✗${NC} Local API proxy is NOT responding"
    echo "   Action: Start the API proxy service"
    echo "   Command: cd ~/agent-v2/frontend && python3 api_server.py &"
fi
echo ""

# Test 2: Remote Backend Connectivity
echo -e "${YELLOW}[TEST 2]${NC} Testing Remote Backend Connectivity..."
BACKEND_IPS=("100.28.125.108" "3.238.232.106")

for IP in "${BACKEND_IPS[@]}"; do
    echo "   Testing $IP:5000..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://${IP}:5000/health 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "   ${GREEN}✓${NC} $IP:5000 - HTTP $HTTP_CODE (OK)"
    elif [ "$HTTP_CODE" = "403" ]; then
        echo -e "   ${YELLOW}⚠${NC} $IP:5000 - HTTP $HTTP_CODE (Forbidden - may require IP whitelist)"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "   ${RED}✗${NC} $IP:5000 - Connection failed (timeout/refused)"
    else
        echo -e "   ${YELLOW}⚠${NC} $IP:5000 - HTTP $HTTP_CODE"
    fi
done
echo ""

# Test 3: Replicas Endpoint (terminated status)
echo -e "${YELLOW}[TEST 3]${NC} Testing Replicas Endpoint (status=terminated)..."
if [ -n "$AGENT_ID" ]; then
    ENDPOINT="$SERVER_URL/api/agents/$AGENT_ID/replicas?status=terminated"
    echo "   Endpoint: $ENDPOINT"

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $CLIENT_TOKEN" \
        -H "Content-Type: application/json" \
        "$ENDPOINT" 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "   ${GREEN}✓${NC} Endpoint responding (HTTP 200)"
        REPLICA_COUNT=$(echo "$BODY" | jq -r '.replicas | length' 2>/dev/null || echo "0")
        echo "   Replicas pending termination: $REPLICA_COUNT"
        if [ "$REPLICA_COUNT" != "0" ]; then
            echo "$BODY" | jq '.replicas' 2>/dev/null || echo "$BODY"
        fi
    else
        echo -e "   ${RED}✗${NC} Endpoint failed (HTTP $HTTP_CODE)"
        echo "   Response: $BODY"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} Cannot test - Agent ID not found"
fi
echo ""

# Test 4: Replicas Endpoint (launching status)
echo -e "${YELLOW}[TEST 4]${NC} Testing Replicas Endpoint (status=launching)..."
if [ -n "$AGENT_ID" ]; then
    ENDPOINT="$SERVER_URL/api/agents/$AGENT_ID/replicas?status=launching"

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $CLIENT_TOKEN" \
        -H "Content-Type: application/json" \
        "$ENDPOINT" 2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "   ${GREEN}✓${NC} Endpoint responding (HTTP 200)"
        REPLICA_COUNT=$(echo "$BODY" | jq -r '.replicas | length' 2>/dev/null || echo "0")
        echo "   Replicas pending launch: $REPLICA_COUNT"
    else
        echo -e "   ${RED}✗${NC} Endpoint failed (HTTP $HTTP_CODE)"
    fi
fi
echo ""

# Test 5: Check Agent Logs for Replica Termination Worker
echo -e "${YELLOW}[TEST 5]${NC} Checking Agent Logs for Replica Termination Worker..."
if [ -f /var/log/spot-optimizer/agent-error.log ]; then
    # Check if worker started
    if grep -q "Started worker: ReplicaTermination" /var/log/spot-optimizer/agent-error.log; then
        echo -e "   ${GREEN}✓${NC} ReplicaTermination worker is started"
    else
        echo -e "   ${RED}✗${NC} ReplicaTermination worker NOT found in logs"
        echo "   Action: Restart the agent to load new worker"
    fi

    # Check for recent termination activity
    RECENT_LOGS=$(grep "REPLICA TERMINATION\|replica.*termination\|Successfully terminated" /var/log/spot-optimizer/agent-error.log | tail -5)
    if [ -n "$RECENT_LOGS" ]; then
        echo ""
        echo "   Recent termination activity:"
        echo "$RECENT_LOGS" | sed 's/^/   /'
    fi
else
    echo -e "   ${YELLOW}⚠${NC} Cannot access agent logs"
fi
echo ""

# Summary and Recommendations
echo "═══════════════════════════════════════════════════════════════"
echo "  Summary and Recommendations"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if local proxy is running
if ! curl -s --connect-timeout 3 http://localhost:5000/health > /dev/null 2>&1; then
    echo -e "${RED}[ACTION REQUIRED]${NC} Local API Proxy is not running"
    echo "   1. Start the API proxy:"
    echo "      cd ~/agent-v2/frontend"
    echo "      python3 api_server.py > /var/log/spot-optimizer/api.log 2>&1 &"
    echo ""
    echo "   2. Or use systemd if configured:"
    echo "      sudo systemctl start spot-optimizer-api"
    echo ""
fi

# Check if agent has new code
if ! grep -q "_replica_termination_worker" /opt/spot-optimizer-agent/spot_optimizer_agent.py 2>/dev/null; then
    echo -e "${RED}[ACTION REQUIRED]${NC} Agent code needs to be updated"
    echo "   1. Copy new agent code:"
    echo "      sudo cp ~/agent-v2/backend/spot_optimizer_agent.py /opt/spot-optimizer-agent/"
    echo ""
    echo "   2. Restart agent:"
    echo "      sudo systemctl restart spot-optimizer-agent"
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "To test replica termination:"
echo "  1. Ensure all services are running"
echo "  2. Create a manual replica in the UI"
echo "  3. Turn off the manual replica toggle"
echo "  4. Watch logs: tail -f /var/log/spot-optimizer/agent-error.log"
echo "  5. Within 30 seconds, you should see termination logs"
echo ""
