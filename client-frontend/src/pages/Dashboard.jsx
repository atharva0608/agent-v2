import React, { useState, useEffect } from 'react';
import apiClient from '../services/apiClient';
import StatCard from '../components/StatCard';
import AgentCard from '../components/AgentCard';
import InstanceCard from '../components/InstanceCard';
import LoadingSpinner from '../components/LoadingSpinner';

const Dashboard = () => {
  const [loading, setLoading] = useState(true);
  const [clientInfo, setClientInfo] = useState(null);
  const [agents, setAgents] = useState([]);
  const [instances, setInstances] = useState([]);
  const [savings, setSavings] = useState(null);
  const [stats, setStats] = useState(null);
  const [lastUpdate, setLastUpdate] = useState(null);

  const fetchAllData = async () => {
    try {
      setLoading(true);

      // Fetch all data in parallel
      const [
        clientInfoData,
        agentsData,
        instancesData,
        savingsData,
        statsData
      ] = await Promise.all([
        apiClient.getClientInfo(),
        apiClient.getClientAgents(),
        apiClient.getClientInstances(),
        apiClient.getClientSavings(),
        apiClient.getClientStats()
      ]);

      setClientInfo(clientInfoData);
      setAgents(agentsData);
      setInstances(instancesData);
      setSavings(savingsData);
      setStats(statsData);
      setLastUpdate(new Date());
    } catch (error) {
      console.error('Failed to fetch data:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAllData();

    // Auto-refresh every 15 seconds
    const interval = setInterval(fetchAllData, 15000);

    return () => clearInterval(interval);
  }, []);

  if (loading && !clientInfo) {
    return <LoadingSpinner message="Loading dashboard..." />;
  }

  const config = apiClient.getConfig();

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold text-gray-900">
                Spot Optimizer - Client Dashboard
              </h1>
              <p className="text-sm text-gray-500 mt-1">
                {clientInfo?.name || 'Client Dashboard'}
              </p>
            </div>
            <div className="text-right">
              <button
                onClick={fetchAllData}
                className="btn btn-secondary text-sm"
                disabled={loading}
              >
                {loading ? 'Refreshing...' : 'Refresh'}
              </button>
              {lastUpdate && (
                <p className="text-xs text-gray-500 mt-1">
                  Last update: {lastUpdate.toLocaleTimeString()}
                </p>
              )}
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Stats Overview */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <StatCard
            title="Active Agents"
            value={agents.filter(a => a.status === 'online').length}
            subtitle={`${agents.length} total`}
            color="blue"
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            }
          />

          <StatCard
            title="Running Instances"
            value={instances.filter(i => i.state === 'running').length}
            subtitle={`${instances.length} total`}
            color="green"
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
              </svg>
            }
          />

          <StatCard
            title="Spot Instances"
            value={instances.filter(i => i.mode === 'spot').length}
            subtitle={`${instances.filter(i => i.mode === 'ondemand').length} on-demand`}
            color="purple"
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            }
          />

          <StatCard
            title="Total Savings"
            value={savings?.total_savings ? `$${savings.total_savings.toFixed(2)}` : '$0.00'}
            subtitle={savings?.savings_percentage ? `${savings.savings_percentage.toFixed(1)}% saved` : 'No data'}
            color="green"
            icon={
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            }
          />
        </div>

        {/* Agents Section */}
        <div className="mb-8">
          <h2 className="text-xl font-bold text-gray-900 mb-4">
            Active Agents ({agents.length})
          </h2>

          {agents.length === 0 ? (
            <div className="card text-center py-12">
              <p className="text-gray-500">No agents found</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {agents.map((agent) => (
                <AgentCard key={agent.id || agent.instance_id} agent={agent} />
              ))}
            </div>
          )}
        </div>

        {/* Instances Section */}
        <div className="mb-8">
          <h2 className="text-xl font-bold text-gray-900 mb-4">
            Instances ({instances.length})
          </h2>

          {instances.length === 0 ? (
            <div className="card text-center py-12">
              <p className="text-gray-500">No instances found</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {instances.map((instance) => (
                <InstanceCard key={instance.instance_id} instance={instance} />
              ))}
            </div>
          )}
        </div>

        {/* Footer Info */}
        <div className="card bg-gray-50 border border-gray-200">
          <div className="text-sm text-gray-600">
            <div className="flex items-center justify-between">
              <div>
                <p><strong>Client ID:</strong> {config.clientId}</p>
                <p className="mt-1"><strong>Central Server:</strong> {config.baseURL}</p>
              </div>
              <div className="text-right">
                <p className="text-xs text-gray-500">
                  Auto-refresh enabled (15s interval)
                </p>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

export default Dashboard;
