import axios from 'axios';

// Get configuration from environment variables or use defaults
const CENTRAL_SERVER_URL = import.meta.env.VITE_CENTRAL_SERVER_URL || 'http://localhost:5000';
const CLIENT_TOKEN = import.meta.env.VITE_CLIENT_TOKEN || '';
const CLIENT_ID = import.meta.env.VITE_CLIENT_ID || '';

class APIClient {
  constructor() {
    this.baseURL = CENTRAL_SERVER_URL;
    this.clientId = CLIENT_ID;

    this.client = axios.create({
      baseURL: this.baseURL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${CLIENT_TOKEN}`
      }
    });

    // Add response interceptor for error handling
    this.client.interceptors.response.use(
      response => response,
      error => {
        console.error('API Error:', error);
        return Promise.reject(error);
      }
    );
  }

  // ============================================================================
  // CLIENT INFO
  // ============================================================================

  async getClientInfo() {
    try {
      const response = await this.client.get(`/api/clients/${this.clientId}`);
      return response.data;
    } catch (error) {
      console.error('Failed to fetch client info:', error);
      return null;
    }
  }

  // ============================================================================
  // AGENTS
  // ============================================================================

  async getClientAgents() {
    try {
      const response = await this.client.get(`/api/clients/${this.clientId}/agents`);
      return response.data.agents || response.data.data || [];
    } catch (error) {
      console.error('Failed to fetch agents:', error);
      return [];
    }
  }

  // ============================================================================
  // INSTANCES
  // ============================================================================

  async getClientInstances() {
    try {
      const response = await this.client.get(`/api/clients/${this.clientId}/instances`);
      return response.data.instances || response.data.data || [];
    } catch (error) {
      console.error('Failed to fetch instances:', error);
      return [];
    }
  }

  // ============================================================================
  // SAVINGS
  // ============================================================================

  async getClientSavings() {
    try {
      const response = await this.client.get(`/api/clients/${this.clientId}/savings`);
      return response.data;
    } catch (error) {
      console.error('Failed to fetch savings:', error);
      return null;
    }
  }

  // ============================================================================
  // HISTORY
  // ============================================================================

  async getClientHistory() {
    try {
      const response = await this.client.get(`/api/clients/${this.clientId}/history`);
      return response.data.history || response.data.data || [];
    } catch (error) {
      console.error('Failed to fetch history:', error);
      return [];
    }
  }

  // ============================================================================
  // STATISTICS
  // ============================================================================

  async getClientStats() {
    try {
      const response = await this.client.get(`/api/clients/${this.clientId}/stats`);
      return response.data;
    } catch (error) {
      console.error('Failed to fetch stats:', error);
      return null;
    }
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  async executeSwitchAction(switchData) {
    try {
      const response = await this.client.post(
        `/api/clients/${this.clientId}/execute-switch`,
        switchData
      );
      return response.data;
    } catch (error) {
      console.error('Failed to execute switch:', error);
      throw error;
    }
  }

  // ============================================================================
  // CONFIG
  // ============================================================================

  getConfig() {
    return {
      baseURL: this.baseURL,
      clientId: this.clientId
    };
  }
}

// Create and export singleton instance
const apiClient = new APIClient();
export default apiClient;
