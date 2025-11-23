import React, { useState, useEffect } from 'react';
import { Server, Play, Pause, RefreshCw, Copy, Settings, Trash2 } from 'lucide-react';
import StatCard from '../components/common/StatCard';
import LoadingSpinner from '../components/common/LoadingSpinner';
import Button from '../components/common/Button';
import Badge from '../components/common/Badge';
import EmptyState from '../components/common/EmptyState';
import api from '../services/api';

const AgentsPage = () => {
  const [agents, setAgents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedAgent, setSelectedAgent] = useState(null);
  const [showSwitchModal, setShowSwitchModal] = useState(false);
  const [showReplicaModal, setShowReplicaModal] = useState(false);

  const loadAgents = async () => {
    setLoading(true);
    try {
      const data = await api.getAgents();
      setAgents(data.agents || []);
    } catch (error) {
      console.error('Failed to load agents:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadAgents();
    const interval = setInterval(loadAgents, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleToggleAgent = async (agent) => {
    try {
      await api.toggleAgent(agent.id);
      await loadAgents();
    } catch (error) {
      console.error('Failed to toggle agent:', error);
      alert('Failed to toggle agent');
    }
  };

  const handleSwitch = async (agent, targetMode) => {
    if (!confirm(`Switch ${agent.hostname} to ${targetMode}?`)) return;

    try {
      await api.switchAgent(agent.id, targetMode, null, 0);
      alert('Switch initiated successfully');
      await loadAgents();
    } catch (error) {
      console.error('Failed to switch:', error);
      alert('Failed to initiate switch');
    }
  };

  if (loading) {
    return <LoadingSpinner message="Loading agents..." />;
  }

  const onlineAgents = agents.filter(a => a.status === 'online').length;
  const spotAgents = agents.filter(a => a.current_mode === 'spot').length;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h2 className="text-3xl font-bold text-gray-900">Agents</h2>
        <p className="text-gray-600 mt-1">Manage your spot optimizer agents</p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <StatCard
          title="Total Agents"
          value={agents.length}
          icon={Server}
          color="blue"
        />
        <StatCard
          title="Online"
          value={onlineAgents}
          icon={Play}
          color="green"
        />
        <StatCard
          title="On Spot"
          value={spotAgents}
          icon={RefreshCw}
          color="purple"
        />
      </div>

      {/* Agents List */}
      {agents.length === 0 ? (
        <EmptyState
          icon={Server}
          title="No agents found"
          message="No agents are currently registered"
        />
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {agents.map((agent) => (
            <div key={agent.id} className="bg-white rounded-xl shadow-lg p-6 border-l-4 border-blue-500">
              {/* Agent Header */}
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h3 className="text-lg font-semibold text-gray-900">{agent.hostname}</h3>
                  <p className="text-sm text-gray-600">{agent.instance_id}</p>
                </div>
                <Badge variant={agent.status === 'online' ? 'success' : 'danger'}>
                  {agent.status}
                </Badge>
              </div>

              {/* Agent Info */}
              <div className="grid grid-cols-2 gap-4 mb-4 text-sm">
                <div>
                  <span className="text-gray-600">Type:</span>
                  <p className="font-medium">{agent.instance_type}</p>
                </div>
                <div>
                  <span className="text-gray-600">Mode:</span>
                  <p className="font-medium">
                    <Badge variant={agent.current_mode === 'spot' ? 'success' : 'info'}>
                      {agent.current_mode}
                    </Badge>
                  </p>
                </div>
                <div>
                  <span className="text-gray-600">Region:</span>
                  <p className="font-medium">{agent.region}</p>
                </div>
                <div>
                  <span className="text-gray-600">AZ:</span>
                  <p className="font-medium">{agent.az}</p>
                </div>
              </div>

              {/* Actions */}
              <div className="flex flex-wrap gap-2 pt-4 border-t">
                <Button
                  size="sm"
                  variant={agent.status === 'online' ? 'danger' : 'success'}
                  onClick={() => handleToggleAgent(agent)}
                >
                  {agent.status === 'online' ? 'Disable' : 'Enable'}
                </Button>
                <Button
                  size="sm"
                  variant="primary"
                  disabled={agent.status !== 'online'}
                  onClick={() => handleSwitch(agent, agent.current_mode === 'spot' ? 'ondemand' : 'spot')}
                >
                  Switch to {agent.current_mode === 'spot' ? 'On-Demand' : 'Spot'}
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={agent.status !== 'online'}
                  icon={Copy}
                >
                  Replica
                </Button>
                <Button
                  size="sm"
                  variant="secondary"
                  icon={Settings}
                >
                  Settings
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default AgentsPage;
