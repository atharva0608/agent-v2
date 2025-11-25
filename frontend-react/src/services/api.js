import { API_CONFIG } from '../config/api';

class APIService {
  constructor(baseURL) {
    this.baseURL = baseURL;
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;

    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      return await response.json();
    } catch (error) {
      console.error(`API request failed: ${endpoint}`, error);
      throw error;
    }
  }

  // Agent methods
  async getAgents() {
    return this.request(API_CONFIG.ENDPOINTS.AGENTS);
  }

  async getAgentStats() {
    return this.request(API_CONFIG.ENDPOINTS.AGENT_STATS);
  }

  async toggleAgent(agentId) {
    return this.request(API_CONFIG.ENDPOINTS.AGENT_TOGGLE(agentId), {
      method: 'POST',
    });
  }

  async updateAgentSettings(agentId, settings) {
    return this.request(API_CONFIG.ENDPOINTS.AGENT_SETTINGS(agentId), {
      method: 'PUT',
      body: JSON.stringify(settings),
    });
  }

  // Switch methods
  async switchAgent(agentId, targetMode, targetPoolId, terminateWaitSeconds) {
    return this.request(API_CONFIG.ENDPOINTS.SWITCH(agentId), {
      method: 'POST',
      body: JSON.stringify({
        target_mode: targetMode,
        target_pool_id: targetPoolId,
        terminate_wait_seconds: terminateWaitSeconds,
      }),
    });
  }

  async getSwitchHistory(agentId, limit = 20) {
    return this.request(`${API_CONFIG.ENDPOINTS.SWITCH_HISTORY(agentId)}?limit=${limit}`);
  }

  // Replica methods
  async getReplicas(agentId) {
    return this.request(API_CONFIG.ENDPOINTS.REPLICAS(agentId));
  }

  async createReplica(agentId, targetPoolId) {
    return this.request(API_CONFIG.ENDPOINTS.REPLICA_CREATE(agentId), {
      method: 'POST',
      body: JSON.stringify({
        target_pool_id: targetPoolId,
      }),
    });
  }

  async promoteReplica(agentId, replicaId) {
    return this.request(API_CONFIG.ENDPOINTS.REPLICA_PROMOTE(agentId, replicaId), {
      method: 'POST',
    });
  }

  async deleteReplica(agentId, replicaId) {
    return this.request(API_CONFIG.ENDPOINTS.REPLICA_DELETE(agentId, replicaId), {
      method: 'DELETE',
    });
  }

  // Pricing methods
  async getPricing() {
    return this.request(API_CONFIG.ENDPOINTS.PRICING);
  }

  async getPricingHistory(days = 7) {
    return this.request(`${API_CONFIG.ENDPOINTS.PRICING_HISTORY}?days=${days}`);
  }

  // Stats methods
  async getSavings() {
    return this.request(API_CONFIG.ENDPOINTS.SAVINGS);
  }

  async getUptime() {
    return this.request(API_CONFIG.ENDPOINTS.UPTIME);
  }
}

const api = new APIService(API_CONFIG.BASE_URL);

export default api;
