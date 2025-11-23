import React, { useState, useEffect } from 'react';
import { Server, DollarSign, Clock, TrendingUp, RefreshCw, Activity } from 'lucide-react';
import { LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import StatCard from '../components/common/StatCard';
import LoadingSpinner from '../components/common/LoadingSpinner';
import Button from '../components/common/Button';
import Badge from '../components/common/Badge';
import api from '../services/api';

const Dashboard = () => {
  const [stats, setStats] = useState(null);
  const [pricingHistory, setPricingHistory] = useState([]);
  const [switchHistory, setSwitchHistory] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = async () => {
    setLoading(true);
    try {
      const [agentsData, savingsData, pricingData] = await Promise.all([
        api.getAgents(),
        api.getSavings(),
        api.getPricingHistory(7)
      ]);

      // Calculate stats from agents
      const agents = agentsData.agents || [];
      const onlineAgents = agents.filter(a => a.status === 'online').length;
      const spotAgents = agents.filter(a => a.current_mode === 'spot').length;

      setStats({
        totalAgents: agents.length,
        onlineAgents,
        spotAgents,
        savings: savingsData.total_savings || 0,
        uptime: savingsData.uptime_percentage || 0,
      });

      setPricingHistory(pricingData.history || []);

      // Get switch history for first agent if available
      if (agents.length > 0) {
        const history = await api.getSwitchHistory(agents[0].id, 10);
        setSwitchHistory(history.switches || []);
      }
    } catch (error) {
      console.error('Failed to load dashboard data:', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    loadData();

    const interval = setInterval(loadData, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleRefresh = async () => {
    setRefreshing(true);
    await loadData();
  };

  if (loading) {
    return <LoadingSpinner message="Loading dashboard..." />;
  }

  // Handle loading states and null data
  const safeStats = stats || {
    totalAgents: 0,
    onlineAgents: 0,
    spotAgents: 0,
    savings: 0,
    uptime: 0
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-3xl font-bold text-gray-900">Dashboard</h2>
          <p className="text-gray-600 mt-1">Overview of your spot optimizer agents</p>
        </div>
        <Button
          icon={RefreshCw}
          onClick={handleRefresh}
          disabled={refreshing}
          variant="outline"
        >
          {refreshing ? 'Refreshing...' : 'Refresh'}
        </Button>
      </div>

      {/* Connection Error Warning */}
      {!stats && (
        <div className="bg-yellow-50 border-l-4 border-yellow-500 p-4 rounded-lg">
          <div className="flex items-center">
            <Activity className="w-5 h-5 text-yellow-600 mr-3" />
            <p className="text-yellow-800">
              Unable to connect to backend API. Please check if the Flask API server is running on port 5000.
            </p>
          </div>
        </div>
      )}

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          title="Total Agents"
          value={safeStats.totalAgents}
          icon={Server}
          trend="up"
          trendValue={`${safeStats.onlineAgents} online`}
          color="blue"
        />
        <StatCard
          title="Spot Instances"
          value={safeStats.spotAgents}
          icon={TrendingUp}
          trend="up"
          trendValue={`${Math.round((safeStats.spotAgents / Math.max(safeStats.totalAgents, 1)) * 100)}% of total`}
          color="green"
        />
        <StatCard
          title="Total Savings"
          value={`$${safeStats.savings.toFixed(2)}`}
          icon={DollarSign}
          trend="up"
          trendValue="This month"
          color="purple"
        />
        <StatCard
          title="Uptime"
          value={`${safeStats.uptime.toFixed(1)}%`}
          icon={Clock}
          trend={safeStats.uptime > 99 ? 'up' : 'neutral'}
          trendValue={safeStats.uptime > 99 ? 'Excellent' : 'Good'}
          color="yellow"
        />
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Pricing Chart */}
        <div className="bg-white rounded-xl shadow-lg p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Spot Price Trend (7 days)</h3>
          <ResponsiveContainer width="100%" height={250}>
            <AreaChart data={pricingHistory}>
              <defs>
                <linearGradient id="colorPrice" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3}/>
                  <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis
                dataKey="timestamp"
                stroke="#6b7280"
                tickFormatter={(value) => new Date(value).toLocaleDateString()}
              />
              <YAxis stroke="#6b7280" />
              <Tooltip
                contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px' }}
                labelFormatter={(value) => new Date(value).toLocaleString()}
                formatter={(value) => [`$${value.toFixed(4)}`, 'Spot Price']}
              />
              <Area
                type="monotone"
                dataKey="price"
                stroke="#3b82f6"
                strokeWidth={2}
                fill="url(#colorPrice)"
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Recent Activity */}
        <div className="bg-white rounded-xl shadow-lg p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center">
            <Activity className="w-5 h-5 mr-2" />
            Recent Switches
          </h3>
          <div className="space-y-3 max-h-64 overflow-y-auto">
            {switchHistory.length > 0 ? (
              switchHistory.map((sw, idx) => (
                <div key={idx} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors">
                  <div className="flex items-center space-x-3">
                    <RefreshCw className="w-4 h-4 text-blue-600" />
                    <div>
                      <p className="text-sm font-medium text-gray-900">
                        {sw.old_mode} → {sw.new_mode}
                      </p>
                      <p className="text-xs text-gray-600">
                        {new Date(sw.switched_at).toLocaleString()}
                      </p>
                    </div>
                  </div>
                  <Badge variant={sw.success ? 'success' : 'danger'}>
                    {sw.success ? 'Success' : 'Failed'}
                  </Badge>
                </div>
              ))
            ) : (
              <p className="text-gray-500 text-center py-8">No recent switches</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
