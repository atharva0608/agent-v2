export const API_CONFIG = {
  BASE_URL: window.location.origin,
  ENDPOINTS: {
    // Agent endpoints
    AGENTS: '/api/agents',
    AGENT_STATS: '/api/agents/stats',
    AGENT_HEARTBEAT: (id) => `/api/agents/${id}/heartbeat`,
    AGENT_TOGGLE: (id) => `/api/agents/${id}/toggle`,
    AGENT_SETTINGS: (id) => `/api/agents/${id}/settings`,

    // Switch endpoints
    SWITCH: (id) => `/api/agents/${id}/switch`,
    SWITCH_HISTORY: (id) => `/api/agents/${id}/switch-history`,

    // Replica endpoints
    REPLICAS: (id) => `/api/agents/${id}/replicas`,
    REPLICA_CREATE: (id) => `/api/agents/${id}/replicas`,
    REPLICA_PROMOTE: (id, replicaId) => `/api/agents/${id}/replicas/${replicaId}/promote`,
    REPLICA_DELETE: (id, replicaId) => `/api/agents/${id}/replicas/${replicaId}`,

    // Pricing endpoints
    PRICING: '/api/pricing',
    PRICING_HISTORY: '/api/pricing/history',

    // Stats endpoints
    SAVINGS: '/api/stats/savings',
    UPTIME: '/api/stats/uptime',
  },
  REFRESH_INTERVAL: 30000, // 30 seconds
};
