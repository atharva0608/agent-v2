"""
Complete API Server for Client Dashboard
Matches final-ml backend API structure
"""

import os
from flask import Flask, jsonify, request
from flask_cors import CORS
import requests
from datetime import datetime, timedelta

app = Flask(__name__)
CORS(app)

# Configuration
BACKEND_URL = os.getenv('BACKEND_URL', 'http://100.28.125.108')
CLIENT_TOKEN = os.getenv('CLIENT_TOKEN', '')

def get_headers():
    """Get headers with client token"""
    return {
        'Authorization': f'Bearer {CLIENT_TOKEN}',
        'Content-Type': 'application/json'
    }

def proxy_request(endpoint, method='GET', **kwargs):
    """Proxy request to backend"""
    try:
        url = f"{BACKEND_URL}{endpoint}"
        response = requests.request(method, url, headers=get_headers(), timeout=10, **kwargs)
        if response.status_code == 200:
            return response.json()
        return {'error': f'Request failed: {response.status_code}'}
    except Exception as e:
        return {'error': str(e)}

# ============================================================================
# AGENT ENDPOINTS
# ============================================================================

@app.route('/api/agents/register', methods=['POST'])
def register_agent():
    """Register a new agent"""
    data = proxy_request('/api/agents/register', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents', methods=['GET'])
def get_agents():
    """Get all agents for this client"""
    data = proxy_request('/api/client/agents')
    return jsonify(data)

@app.route('/api/agents/<agent_id>', methods=['GET'])
def get_agent(agent_id):
    """Get single agent details"""
    data = proxy_request(f'/api/agents/{agent_id}')
    return jsonify(data)

@app.route('/api/agents/<agent_id>/heartbeat', methods=['POST'])
def agent_heartbeat(agent_id):
    """Receive agent heartbeat"""
    data = proxy_request(f'/api/agents/{agent_id}/heartbeat', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/config', methods=['GET'])
def get_agent_config(agent_id):
    """Get agent configuration"""
    data = proxy_request(f'/api/agents/{agent_id}/config')
    return jsonify(data)

@app.route('/api/agents/<agent_id>/pending-commands', methods=['GET'])
def get_pending_commands(agent_id):
    """Get pending commands for agent"""
    data = proxy_request(f'/api/agents/{agent_id}/pending-commands')
    return jsonify(data)

@app.route('/api/agents/<agent_id>/commands/<command_id>/executed', methods=['POST'])
def mark_command_executed(agent_id, command_id):
    """Mark command as executed"""
    data = proxy_request(f'/api/agents/{agent_id}/commands/{command_id}/executed', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/pricing-report', methods=['POST'])
def pricing_report(agent_id):
    """Receive pricing report from agent"""
    data = proxy_request(f'/api/agents/{agent_id}/pricing-report', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/switch-report', methods=['POST'])
def switch_report(agent_id):
    """Receive switch report from agent"""
    data = proxy_request(f'/api/agents/{agent_id}/switch-report', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/cleanup-report', methods=['POST'])
def cleanup_report(agent_id):
    """Receive cleanup report from agent"""
    data = proxy_request(f'/api/agents/{agent_id}/cleanup-report', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/termination-imminent', methods=['POST'])
def termination_imminent(agent_id):
    """Handle spot termination notice"""
    data = proxy_request(f'/api/agents/{agent_id}/termination-imminent', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/rebalance-recommendation', methods=['POST'])
def rebalance_recommendation(agent_id):
    """Handle rebalance recommendation"""
    data = proxy_request(f'/api/agents/{agent_id}/rebalance-recommendation', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/create-emergency-replica', methods=['POST'])
def create_emergency_replica(agent_id):
    """Create emergency replica"""
    data = proxy_request(f'/api/agents/{agent_id}/create-emergency-replica', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/stats', methods=['GET'])
def get_agent_stats():
    """Get agent statistics"""
    agents_data = proxy_request('/api/client/agents')
    agents = agents_data.get('agents', [])

    online = [a for a in agents if a.get('status') == 'online']
    spot = [a for a in agents if a.get('current_mode') == 'spot']

    stats = {
        'total_agents': len(agents),
        'online_agents': len(online),
        'offline_agents': len(agents) - len(online),
        'spot_agents': len(spot),
        'ondemand_agents': len(agents) - len(spot),
    }
    return jsonify(stats)

@app.route('/api/agents/<agent_id>/toggle', methods=['POST'])
def toggle_agent(agent_id):
    """Toggle agent enabled/disabled"""
    data = proxy_request(f'/api/agents/{agent_id}/toggle-enabled', method='POST')
    return jsonify(data)

@app.route('/api/agents/<agent_id>/switch', methods=['POST'])
def switch_agent(agent_id):
    """Switch agent mode"""
    data = proxy_request(f'/api/agents/{agent_id}/switch', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/settings', methods=['PUT'])
def update_agent_settings(agent_id):
    """Update agent settings"""
    data = proxy_request(f'/api/agents/{agent_id}/settings', method='PUT', json=request.json)
    return jsonify(data)

# ============================================================================
# REPLICA ENDPOINTS
# ============================================================================

@app.route('/api/agents/<agent_id>/replicas', methods=['GET', 'POST'])
def handle_replicas(agent_id):
    """Get or create replicas"""
    if request.method == 'POST':
        data = proxy_request(f'/api/agents/{agent_id}/replicas', method='POST', json=request.json)
    else:
        # Pass query parameters (e.g., ?status=launching)
        query_string = request.query_string.decode('utf-8')
        endpoint = f'/api/agents/{agent_id}/replicas'
        if query_string:
            endpoint = f'{endpoint}?{query_string}'
        data = proxy_request(endpoint)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/replica-config', methods=['GET'])
def get_replica_config(agent_id):
    """Get replica configuration"""
    data = proxy_request(f'/api/agents/{agent_id}/replica-config')
    return jsonify(data)

@app.route('/api/agents/<agent_id>/replicas/<replica_id>', methods=['PUT', 'DELETE'])
def handle_replica(agent_id, replica_id):
    """Update or delete replica"""
    if request.method == 'PUT':
        data = proxy_request(f'/api/agents/{agent_id}/replicas/{replica_id}', method='PUT', json=request.json)
    else:  # DELETE
        data = proxy_request(f'/api/agents/{agent_id}/replicas/{replica_id}', method='DELETE')
    return jsonify(data)

@app.route('/api/agents/<agent_id>/replicas/<replica_id>/status', methods=['POST'])
def update_replica_status(agent_id, replica_id):
    """Update replica status"""
    data = proxy_request(f'/api/agents/{agent_id}/replicas/{replica_id}/status', method='POST', json=request.json)
    return jsonify(data)

@app.route('/api/agents/<agent_id>/replicas/<replica_id>/promote', methods=['POST'])
def promote_replica(agent_id, replica_id):
    """Promote replica to primary"""
    data = proxy_request(f'/api/agents/{agent_id}/replicas/{replica_id}/promote', method='POST')
    return jsonify(data)

# ============================================================================
# STATS & SAVINGS ENDPOINTS
# ============================================================================

@app.route('/api/stats/savings', methods=['GET'])
def get_savings():
    """Get savings stats"""
    data = proxy_request('/api/client/savings')
    if 'error' in data:
        return jsonify({'total_savings': 0, 'monthly_savings': 0, 'uptime_percentage': 99.9})
    return jsonify(data)

@app.route('/api/stats/overview', methods=['GET'])
def get_overview():
    """Get overview stats"""
    agents_data = proxy_request('/api/client/agents')
    savings_data = proxy_request('/api/client/savings')

    agents = agents_data.get('agents', [])

    return jsonify({
        'total_instances': len(agents),
        'online_agents': len([a for a in agents if a.get('status') == 'online']),
        'total_agents': len(agents),
        'spot_instances': len([a for a in agents if a.get('current_mode') == 'spot']),
        'total_savings': savings_data.get('total_savings', 0),
        'monthly_savings': savings_data.get('monthly_savings', 0),
        'uptime_percentage': savings_data.get('uptime_percentage', 99.9)
    })

# ============================================================================
# PRICING ENDPOINTS
# ============================================================================

@app.route('/api/pricing', methods=['GET'])
def get_pricing():
    """Get current pricing"""
    data = proxy_request('/api/client/pricing')
    if 'error' in data:
        return jsonify({'pools': [], 'current_price': None})
    return jsonify(data)

@app.route('/api/pricing/history', methods=['GET'])
def get_pricing_history():
    """Get pricing history (7 days default)"""
    days = request.args.get('days', 7)
    agent_id = request.args.get('agent_id')  # Optional: filter by specific agent

    # Build query parameters
    params = {'days': days}
    if agent_id:
        params['agent_id'] = agent_id

    query_string = '&'.join([f'{k}={v}' for k, v in params.items()])
    data = proxy_request(f'/api/client/pricing-history?{query_string}')

    if 'error' in data:
        # Return empty data if backend unavailable
        return jsonify({'history': []})
    return jsonify(data)

# ============================================================================
# SWITCH HISTORY & CHARTS
# ============================================================================

@app.route('/api/switches/history', methods=['GET'])
def get_switch_history():
    """Get switch history"""
    limit = request.args.get('limit', 20)
    data = proxy_request(f'/api/client/switches?limit={limit}')
    if 'error' in data:
        return jsonify({'switches': []})
    return jsonify(data)

@app.route('/api/charts/savings-trend', methods=['GET'])
def get_savings_trend():
    """Get savings trend chart data"""
    period = request.args.get('period', '30d')
    data = proxy_request(f'/api/client/charts/savings-trend?period={period}')
    if 'error' in data:
        return jsonify({'data': []})
    return jsonify(data)

@app.route('/api/charts/mode-distribution', methods=['GET'])
def get_mode_distribution():
    """Get instance mode distribution"""
    agents_data = proxy_request('/api/client/agents')
    agents = agents_data.get('agents', [])

    spot_count = len([a for a in agents if a.get('current_mode') == 'spot'])
    ondemand_count = len(agents) - spot_count

    return jsonify({
        'data': [
            {'mode': 'spot', 'count': spot_count},
            {'mode': 'ondemand', 'count': ondemand_count}
        ]
    })

@app.route('/api/charts/switch-frequency', methods=['GET'])
def get_switch_frequency():
    """Get switch frequency over time"""
    days = request.args.get('days', 30)
    data = proxy_request(f'/api/client/charts/switch-frequency?days={days}')
    if 'error' in data:
        return jsonify({'data': []})
    return jsonify(data)

# ============================================================================
# INSTANCES ENDPOINTS
# ============================================================================

@app.route('/api/instances', methods=['GET'])
def get_instances():
    """Get all instances"""
    data = proxy_request('/api/client/instances')
    return jsonify(data)

@app.route('/api/instances/<instance_id>', methods=['GET'])
def get_instance(instance_id):
    """Get instance details"""
    data = proxy_request(f'/api/instances/{instance_id}')
    return jsonify(data)

@app.route('/api/client/instances/<instance_id>/available-options', methods=['GET'])
def get_instance_available_options(instance_id):
    """Get available spot/on-demand options for instance"""
    data = proxy_request(f'/api/client/instances/{instance_id}/available-options')
    return jsonify(data)

# ============================================================================
# HEALTH & INFO
# ============================================================================

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({
        'status': 'ok',
        'backend': BACKEND_URL,
        'token_configured': bool(CLIENT_TOKEN)
    })

@app.route('/api/client/info', methods=['GET'])
def client_info():
    """Get client info"""
    data = proxy_request('/api/client/validate')
    return jsonify(data)

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
