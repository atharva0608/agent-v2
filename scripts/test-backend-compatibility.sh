#!/bin/bash
#
# Test Backend Compatibility with Final-ML
# This script tests if the backend has all required endpoints
#

BACKEND_URL="${1:-http://100.28.125.108}"
TOKEN="${2:-demo-token}"

echo "=================================="
echo "Backend Compatibility Test"
echo "=================================="
echo "Backend: $BACKEND_URL"
echo "Token: ${TOKEN:0:10}..."
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3

    echo -n "Testing $method $endpoint ... "

    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" -X GET \
            -H "Authorization: Bearer $TOKEN" \
            "$BACKEND_URL$endpoint" 2>/dev/null)
    else
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d '{}' \
            "$BACKEND_URL$endpoint" 2>/dev/null)
    fi

    status_code=$(echo "$response" | tail -n1)

    # Endpoints should return 200, 400, or 422 (validation error) but NOT 404
    if [ "$status_code" = "404" ]; then
        echo -e "${RED}✗ NOT FOUND${NC} - $description"
        return 1
    elif [ "$status_code" = "000" ]; then
        echo -e "${RED}✗ CONNECTION FAILED${NC} - $description"
        return 1
    else
        echo -e "${GREEN}✓ EXISTS${NC} (HTTP $status_code) - $description"
        return 0
    fi
}

echo "Core Agent Endpoints:"
echo "--------------------"
test_endpoint POST "/api/agents/register" "Agent registration"
test_endpoint POST "/api/agents/test-agent-id/heartbeat" "Agent heartbeat"
test_endpoint GET "/api/agents/test-agent-id/config" "Agent configuration"
test_endpoint GET "/api/agents/test-agent-id/pending-commands" "Command polling"
test_endpoint POST "/api/agents/test-agent-id/commands/test-cmd-id/executed" "Command execution"

echo ""
echo "Reporting Endpoints:"
echo "--------------------"
test_endpoint POST "/api/agents/test-agent-id/pricing-report" "Pricing reports"
test_endpoint POST "/api/agents/test-agent-id/switch-report" "Switch reports"
test_endpoint POST "/api/agents/test-agent-id/cleanup-report" "Cleanup reports"

echo ""
echo "Emergency Endpoints:"
echo "--------------------"
test_endpoint POST "/api/agents/test-agent-id/termination-imminent" "Termination notice"
test_endpoint POST "/api/agents/test-agent-id/rebalance-recommendation" "Rebalance recommendation"
test_endpoint POST "/api/agents/test-agent-id/create-emergency-replica" "Emergency replica"

echo ""
echo "Replica Management:"
echo "--------------------"
test_endpoint GET "/api/agents/test-agent-id/replicas" "List replicas"
test_endpoint POST "/api/agents/test-agent-id/replicas" "Create replica"
test_endpoint GET "/api/agents/test-agent-id/replica-config" "Replica config"
test_endpoint PUT "/api/agents/test-agent-id/replicas/test-replica-id" "Update replica"
test_endpoint POST "/api/agents/test-agent-id/replicas/test-replica-id/status" "Replica status"
test_endpoint POST "/api/agents/test-agent-id/replicas/test-replica-id/promote" "Promote replica"

echo ""
echo "Optional Endpoints (ML Features):"
echo "-----------------------------------"
test_endpoint POST "/api/agents/test-agent-id/decide" "ML decision"
test_endpoint GET "/api/agents/test-agent-id/switch-recommendation" "ML recommendation"

echo ""
echo "=================================="
echo "Test Complete"
echo "=================================="
echo ""
echo "If all CORE endpoints show ✓ EXISTS, you're fully compatible!"
echo "If you see ✗ NOT FOUND, the backend needs to be upgraded."
echo ""
