"""
Simple API Server for Client Dashboard
Proxies requests to the central backend
"""

import os
from flask import Flask, jsonify
from flask_cors import CORS
import requests

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

def proxy_request(endpoint):
    """Proxy request to backend"""
    try:
        url = f"{BACKEND_URL}{endpoint}"
        response = requests.get(url, headers=get_headers(), timeout=10)
        return response.json() if response.status_code == 200 else {'error': 'Request failed'}
    except Exception as e:
        return {'error': str(e)}

# ============================================================================
# API ROUTES
# ============================================================================

@app.route('/api/agents', methods=['GET'])
def get_agents():
    """Get all agents"""
    data = proxy_request('/api/client/agents')
    return jsonify(data)

@app.route('/api/agents/stats', methods=['GET'])
def get_agent_stats():
    """Get agent statistics"""
    agents_data = proxy_request('/api/client/agents')
    agents = agents_data.get('agents', [])

    stats = {
        'total_agents': len(agents),
        'online_agents': len([a for a in agents if a.get('status') == 'online']),
        'spot_agents': len([a for a in agents if a.get('current_mode') == 'spot']),
    }
    return jsonify(stats)

@app.route('/api/agents/<agent_id>/toggle', methods=['POST'])
def toggle_agent(agent_id):
    """Toggle agent enabled state"""
    try:
        url = f"{BACKEND_URL}/api/agents/{agent_id}/toggle-enabled"
        response = requests.post(url, headers=get_headers(), timeout=10)
        return jsonify(response.json() if response.status_code == 200 else {'error': 'Failed'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/agents/<agent_id>/switch', methods=['POST'])
def switch_agent(agent_id):
    """Switch agent mode"""
    try:
        from flask import request
        url = f"{BACKEND_URL}/api/agents/{agent_id}/switch"
        response = requests.post(url, headers=get_headers(), json=request.json, timeout=10)
        return jsonify(response.json() if response.status_code == 200 else {'error': 'Failed'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/agents/<agent_id>/replicas', methods=['POST'])
def create_replica(agent_id):
    """Create replica"""
    try:
        from flask import request
        url = f"{BACKEND_URL}/api/agents/{agent_id}/replicas"
        response = requests.post(url, headers=get_headers(), json=request.json, timeout=10)
        return jsonify(response.json() if response.status_code == 200 else {'error': 'Failed'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stats/savings', methods=['GET'])
def get_savings():
    """Get savings stats"""
    data = proxy_request('/api/client/savings')
    return jsonify(data if data else {'total_savings': 0, 'uptime_percentage': 0})

@app.route('/api/pricing', methods=['GET'])
def get_pricing():
    """Get current pricing"""
    data = proxy_request('/api/client/pricing')
    return jsonify(data if data else {'pools': []})

@app.route('/api/pricing/history', methods=['GET'])
def get_pricing_history():
    """Get pricing history"""
    from flask import request
    days = request.args.get('days', 7)
    data = proxy_request(f'/api/client/pricing-history?days={days}')
    return jsonify(data if data else {'history': []})

@app.route('/api/agents/<agent_id>/switch-history', methods=['GET'])
def get_switch_history(agent_id):
    """Get switch history"""
    from flask import request
    limit = request.args.get('limit', 20)
    data = proxy_request(f'/api/agents/{agent_id}/switches?limit={limit}')
    return jsonify(data if data else {'switches': []})

@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({'status': 'ok', 'backend': BACKEND_URL})

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
