import React, { useState, useEffect } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  Area,
  AreaChart
} from 'recharts';
import axios from 'axios';

/**
 * Pricing History Chart Component
 * Shows 7-day pricing history for spot pools and on-demand pricing
 *
 * Features:
 * - Line chart with filled area underneath
 * - Toggle lines on/off by clicking legend
 * - Auto-refresh every 12 hours
 * - Shows pricing for all 3 availability zones + on-demand
 */
const PricingHistoryChart = ({ agentId }) => {
  const [pricingData, setPricingData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);

  // Toggle state for each line
  const [visibleLines, setVisibleLines] = useState({
    'az-1a': true,
    'az-1b': true,
    'az-1c': true,
    'ondemand': true
  });

  // Fetch pricing history from backend
  const fetchPricingHistory = async () => {
    try {
      setLoading(true);
      setError(null);

      const response = await axios.get(`/api/pricing/history`, {
        params: {
          agent_id: agentId,
          days: 7
        }
      });

      // Transform backend data to chart format
      const transformedData = transformPricingData(response.data);
      setPricingData(transformedData);
      setLastUpdated(new Date());

    } catch (err) {
      console.error('Failed to fetch pricing history:', err);
      setError('Failed to load pricing history. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  /**
   * Transform backend pricing data to format suitable for chart
   * Input: { history: [{timestamp, spot_pools, ondemand_price}] }
   * Output: [{time, 'az-1a', 'az-1b', 'az-1c', 'ondemand'}]
   */
  const transformPricingData = (data) => {
    if (!data || !data.history) return [];

    return data.history.map(point => {
      const formattedPoint = {
        time: new Date(point.timestamp).toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
          hour: '2-digit'
        })
      };

      // Add spot pool prices (by AZ)
      if (point.spot_pools && Array.isArray(point.spot_pools)) {
        point.spot_pools.forEach(pool => {
          // Use last part of AZ name (e.g., "us-east-1a" -> "1a")
          const azSuffix = pool.az ? pool.az.slice(-2) : 'unknown';
          const key = `az-${azSuffix}`;
          formattedPoint[key] = parseFloat(pool.price || 0);
        });
      }

      // Add on-demand price
      formattedPoint.ondemand = parseFloat(point.ondemand_price || 0);

      return formattedPoint;
    });
  };

  // Initial fetch
  useEffect(() => {
    if (agentId) {
      fetchPricingHistory();
    }
  }, [agentId]);

  // Auto-refresh every 12 hours
  useEffect(() => {
    const interval = setInterval(() => {
      console.log('Auto-refreshing pricing history...');
      fetchPricingHistory();
    }, 12 * 60 * 60 * 1000); // 12 hours

    return () => clearInterval(interval);
  }, [agentId]);

  // Toggle line visibility
  const toggleLine = (lineKey) => {
    setVisibleLines(prev => ({
      ...prev,
      [lineKey]: !prev[lineKey]
    }));
  };

  // Custom legend with clickable items
  const CustomLegend = ({ payload }) => {
    return (
      <div className="flex justify-center gap-6 mt-4 flex-wrap">
        {payload.map((entry, index) => {
          const isVisible = visibleLines[entry.dataKey];
          return (
            <button
              key={`legend-${index}`}
              onClick={() => toggleLine(entry.dataKey)}
              className={`flex items-center gap-2 px-3 py-1 rounded transition-all ${
                isVisible
                  ? 'opacity-100 hover:bg-gray-100'
                  : 'opacity-40 hover:bg-gray-50'
              }`}
            >
              <span
                className="w-4 h-4 rounded"
                style={{
                  backgroundColor: entry.color,
                  opacity: isVisible ? 1 : 0.3
                }}
              />
              <span className={`text-sm ${isVisible ? 'font-medium' : 'font-normal'}`}>
                {getLegendLabel(entry.dataKey)}
              </span>
            </button>
          );
        })}
      </div>
    );
  };

  // Get human-readable labels
  const getLegendLabel = (key) => {
    const labels = {
      'az-1a': 'AZ us-east-1a (Spot)',
      'az-1b': 'AZ us-east-1b (Spot)',
      'az-1c': 'AZ us-east-1c (Spot)',
      'ondemand': 'On-Demand Price'
    };
    return labels[key] || key;
  };

  // Custom tooltip
  const CustomTooltip = ({ active, payload, label }) => {
    if (!active || !payload || payload.length === 0) return null;

    return (
      <div className="bg-white border border-gray-300 rounded-lg shadow-lg p-4">
        <p className="font-semibold text-gray-900 mb-2">{label}</p>
        {payload.map((entry, index) => {
          if (!visibleLines[entry.dataKey]) return null;
          return (
            <div key={`tooltip-${index}`} className="flex items-center gap-2 py-1">
              <span
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: entry.color }}
              />
              <span className="text-sm text-gray-700">
                {getLegendLabel(entry.dataKey)}:
              </span>
              <span className="text-sm font-semibold text-gray-900">
                ${entry.value.toFixed(4)}/hr
              </span>
            </div>
          );
        })}
      </div>
    );
  };

  if (loading && pricingData.length === 0) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
          <p className="text-gray-600">Loading pricing history...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-6 text-center">
        <p className="text-red-800">{error}</p>
        <button
          onClick={fetchPricingHistory}
          className="mt-4 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
        >
          Retry
        </button>
      </div>
    );
  }

  if (pricingData.length === 0) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-6 text-center">
        <p className="text-gray-600">No pricing history available yet.</p>
        <p className="text-sm text-gray-500 mt-2">
          Data will appear once the agent starts sending pricing reports.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow-lg p-6">
      {/* Header */}
      <div className="flex justify-between items-center mb-6">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">
            7-Day Pricing History
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            {lastUpdated && `Last updated: ${lastUpdated.toLocaleString()}`}
          </p>
        </div>
        <button
          onClick={fetchPricingHistory}
          disabled={loading}
          className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 flex items-center gap-2"
        >
          {loading ? (
            <>
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
              <span>Refreshing...</span>
            </>
          ) : (
            <>
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              <span>Refresh</span>
            </>
          )}
        </button>
      </div>

      {/* Chart */}
      <ResponsiveContainer width="100%" height={400}>
        <AreaChart
          data={pricingData}
          margin={{ top: 10, right: 30, left: 0, bottom: 0 }}
        >
          <defs>
            {/* Gradients for filled areas */}
            <linearGradient id="colorAz1a" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.8}/>
              <stop offset="95%" stopColor="#3b82f6" stopOpacity={0.1}/>
            </linearGradient>
            <linearGradient id="colorAz1b" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#10b981" stopOpacity={0.8}/>
              <stop offset="95%" stopColor="#10b981" stopOpacity={0.1}/>
            </linearGradient>
            <linearGradient id="colorAz1c" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#f59e0b" stopOpacity={0.8}/>
              <stop offset="95%" stopColor="#f59e0b" stopOpacity={0.1}/>
            </linearGradient>
            <linearGradient id="colorOndemand" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#ef4444" stopOpacity={0.8}/>
              <stop offset="95%" stopColor="#ef4444" stopOpacity={0.1}/>
            </linearGradient>
          </defs>

          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />

          <XAxis
            dataKey="time"
            stroke="#6b7280"
            tick={{ fontSize: 12 }}
            tickLine={{ stroke: '#e5e7eb' }}
          />

          <YAxis
            stroke="#6b7280"
            tick={{ fontSize: 12 }}
            tickLine={{ stroke: '#e5e7eb' }}
            tickFormatter={(value) => `$${value.toFixed(3)}`}
            label={{ value: 'Price ($/hour)', angle: -90, position: 'insideLeft' }}
          />

          <Tooltip content={<CustomTooltip />} />

          <Legend content={<CustomLegend />} />

          {/* Spot AZ 1a Line */}
          {visibleLines['az-1a'] && (
            <Area
              type="monotone"
              dataKey="az-1a"
              stroke="#3b82f6"
              strokeWidth={2}
              fill="url(#colorAz1a)"
              fillOpacity={1}
              dot={{ r: 3, fill: '#3b82f6' }}
              activeDot={{ r: 5 }}
            />
          )}

          {/* Spot AZ 1b Line */}
          {visibleLines['az-1b'] && (
            <Area
              type="monotone"
              dataKey="az-1b"
              stroke="#10b981"
              strokeWidth={2}
              fill="url(#colorAz1b)"
              fillOpacity={1}
              dot={{ r: 3, fill: '#10b981' }}
              activeDot={{ r: 5 }}
            />
          )}

          {/* Spot AZ 1c Line */}
          {visibleLines['az-1c'] && (
            <Area
              type="monotone"
              dataKey="az-1c"
              stroke="#f59e0b"
              strokeWidth={2}
              fill="url(#colorAz1c)"
              fillOpacity={1}
              dot={{ r: 3, fill: '#f59e0b' }}
              activeDot={{ r: 5 }}
            />
          )}

          {/* On-Demand Line */}
          {visibleLines['ondemand'] && (
            <Area
              type="monotone"
              dataKey="ondemand"
              stroke="#ef4444"
              strokeWidth={2}
              fill="url(#colorOndemand)"
              fillOpacity={1}
              dot={{ r: 3, fill: '#ef4444' }}
              activeDot={{ r: 5 }}
              strokeDasharray="5 5"
            />
          )}
        </AreaChart>
      </ResponsiveContainer>

      {/* Stats Summary */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6 pt-6 border-t border-gray-200">
        {Object.entries(visibleLines).map(([key, isVisible]) => {
          if (!isVisible) return null;

          const values = pricingData.map(d => d[key]).filter(v => v);
          if (values.length === 0) return null;

          const avg = values.reduce((a, b) => a + b, 0) / values.length;
          const min = Math.min(...values);
          const max = Math.max(...values);

          return (
            <div key={key} className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide mb-2">
                {getLegendLabel(key)}
              </p>
              <div className="space-y-1">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-600">Avg:</span>
                  <span className="font-semibold">${avg.toFixed(4)}/hr</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-600">Min:</span>
                  <span className="font-semibold text-green-600">${min.toFixed(4)}/hr</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-600">Max:</span>
                  <span className="font-semibold text-red-600">${max.toFixed(4)}/hr</span>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Info Footer */}
      <div className="mt-6 pt-6 border-t border-gray-200">
        <p className="text-xs text-gray-500 text-center">
          💡 <strong>Tip:</strong> Click on the legend items to show/hide lines. Data auto-refreshes every 12 hours.
        </p>
      </div>
    </div>
  );
};

export default PricingHistoryChart;
