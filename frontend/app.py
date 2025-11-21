"""
AWS Spot Optimizer - Client Dashboard
=====================================
Client-centric dashboard for monitoring and managing spot instances.
"""

import os
from datetime import datetime, timedelta
from functools import wraps
from flask import Flask, render_template, jsonify, request, redirect, url_for, session, flash
import requests

app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'your-secret-key-change-in-production')

# Configuration
BACKEND_URL = os.getenv('BACKEND_URL', 'http://localhost:5000')

# ============================================================================
# HELPERS
# ============================================================================

def get_auth_headers():
    """Get authorization headers with client token"""
    token = session.get('client_token')
    if token:
        return {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    return {'Content-Type': 'application/json'}

def api_request(method, endpoint, **kwargs):
    """Make API request to backend"""
    url = f"{BACKEND_URL}{endpoint}"
    headers = get_auth_headers()
    try:
        response = requests.request(method, url, headers=headers, timeout=30, **kwargs)
        return response
    except requests.exceptions.RequestException as e:
        return None

def login_required(f):
    """Decorator to require login"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'client_token' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# ============================================================================
# AUTH ROUTES
# ============================================================================

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'POST':
        client_token = request.form.get('client_token')

        # Validate token with backend
        try:
            response = requests.get(
                f"{BACKEND_URL}/api/client/validate",
                headers={'Authorization': f'Bearer {client_token}'},
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()
                session['client_token'] = client_token
                session['client_id'] = data.get('client_id')
                session['client_name'] = data.get('name', 'Client')
                return redirect(url_for('dashboard'))
            else:
                flash('Invalid client token', 'error')
        except Exception as e:
            flash(f'Connection error: {str(e)}', 'error')

    return render_template('login.html')

@app.route('/logout')
def logout():
    """Logout"""
    session.clear()
    return redirect(url_for('login'))

# ============================================================================
# DASHBOARD ROUTES
# ============================================================================

@app.route('/')
@login_required
def dashboard():
    """Main dashboard"""
    return render_template('dashboard.html', client_name=session.get('client_name', 'Client'))

@app.route('/agents')
@login_required
def agents():
    """Agents list page"""
    return render_template('agents.html', client_name=session.get('client_name', 'Client'))

@app.route('/instances')
@login_required
def instances():
    """Instances page"""
    return render_template('instances.html', client_name=session.get('client_name', 'Client'))

@app.route('/switches')
@login_required
def switches():
    """Switch history page"""
    return render_template('switches.html', client_name=session.get('client_name', 'Client'))

@app.route('/replicas')
@login_required
def replicas():
    """Replicas management page"""
    return render_template('replicas.html', client_name=session.get('client_name', 'Client'))

@app.route('/settings')
@login_required
def settings():
    """Settings page"""
    return render_template('settings.html', client_name=session.get('client_name', 'Client'))

# ============================================================================
# API PROXY ROUTES
# ============================================================================

@app.route('/api/dashboard/stats')
@login_required
def api_dashboard_stats():
    """Get dashboard statistics"""
    client_id = session.get('client_id')
    response = api_request('GET', f'/api/client/{client_id}')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to fetch stats'}), 500

@app.route('/api/agents')
@login_required
def api_agents():
    """Get all agents for client"""
    client_id = session.get('client_id')
    response = api_request('GET', f'/api/client/{client_id}/agents')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'agents': []}), 200

@app.route('/api/agents/<agent_id>')
@login_required
def api_agent_detail(agent_id):
    """Get agent details"""
    response = api_request('GET', f'/api/agents/{agent_id}')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Agent not found'}), 404

@app.route('/api/agents/<agent_id>/toggle-enabled', methods=['POST'])
@login_required
def api_toggle_agent(agent_id):
    """Toggle agent enabled status"""
    response = api_request('POST', f'/api/client/agents/{agent_id}/toggle-enabled')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to toggle agent'}), 500

@app.route('/api/agents/<agent_id>/settings', methods=['POST'])
@login_required
def api_update_agent_settings(agent_id):
    """Update agent settings"""
    data = request.json
    response = api_request('POST', f'/api/client/agents/{agent_id}/settings', json=data)

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to update settings'}), 500

@app.route('/api/agents/<agent_id>/switch', methods=['POST'])
@login_required
def api_manual_switch(agent_id):
    """Trigger manual switch"""
    data = request.json
    response = api_request('POST', f'/api/agents/{agent_id}/issue-switch-command', json=data)

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to trigger switch'}), 500

@app.route('/api/instances')
@login_required
def api_instances():
    """Get all instances for client"""
    client_id = session.get('client_id')
    response = api_request('GET', f'/api/client/{client_id}/instances')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'instances': []}), 200

@app.route('/api/instances/<instance_id>/pricing')
@login_required
def api_instance_pricing(instance_id):
    """Get instance pricing details"""
    response = api_request('GET', f'/api/client/instances/{instance_id}/pricing')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Pricing not found'}), 404

@app.route('/api/switches')
@login_required
def api_switches():
    """Get switch history"""
    client_id = session.get('client_id')
    response = api_request('GET', f'/api/client/{client_id}/switches')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'switches': []}), 200

@app.route('/api/replicas')
@login_required
def api_replicas():
    """Get active replicas"""
    client_id = session.get('client_id')
    response = api_request('GET', f'/api/client/{client_id}/replicas')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'replicas': []}), 200

@app.route('/api/agents/<agent_id>/replicas', methods=['POST'])
@login_required
def api_create_replica(agent_id):
    """Create manual replica"""
    data = request.json
    response = api_request('POST', f'/api/agents/{agent_id}/replicas', json=data)

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to create replica'}), 500

@app.route('/api/agents/<agent_id>/replicas/<replica_id>/promote', methods=['POST'])
@login_required
def api_promote_replica(agent_id, replica_id):
    """Promote replica to primary"""
    response = api_request('POST', f'/api/agents/{agent_id}/replicas/{replica_id}/promote')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to promote replica'}), 500

@app.route('/api/agents/<agent_id>/replicas/<replica_id>', methods=['DELETE'])
@login_required
def api_terminate_replica(agent_id, replica_id):
    """Terminate replica"""
    response = api_request('DELETE', f'/api/agents/{agent_id}/replicas/{replica_id}')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'error': 'Failed to terminate replica'}), 500

@app.route('/api/savings')
@login_required
def api_savings():
    """Get savings data"""
    client_id = session.get('client_id')
    response = api_request('GET', f'/api/client/{client_id}/savings')

    if response and response.status_code == 200:
        return jsonify(response.json())
    return jsonify({'total_savings': 0, 'monthly_savings': []}), 200

# ============================================================================
# ERROR HANDLERS
# ============================================================================

@app.errorhandler(404)
def not_found(e):
    return render_template('404.html'), 404

@app.errorhandler(500)
def server_error(e):
    return render_template('500.html'), 500

# ============================================================================
# MAIN
# ============================================================================

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=3000)
