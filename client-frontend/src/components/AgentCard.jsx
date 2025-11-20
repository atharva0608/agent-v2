import React from 'react';

const AgentCard = ({ agent }) => {
  const getStatusBadge = (status) => {
    const badges = {
      online: 'badge badge-success',
      offline: 'badge badge-danger',
      disabled: 'badge badge-warning'
    };
    return badges[status] || 'badge badge-info';
  };

  return (
    <div className="card hover:shadow-lg transition-shadow duration-200">
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">
            {agent.hostname || agent.instance_id}
          </h3>
          <p className="text-sm text-gray-500">
            {agent.instance_type} • {agent.region}
          </p>
        </div>
        <span className={getStatusBadge(agent.status)}>
          {agent.status || 'unknown'}
        </span>
      </div>

      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-gray-600">Instance ID:</span>
          <span className="font-mono text-gray-900">{agent.instance_id}</span>
        </div>

        <div className="flex justify-between text-sm">
          <span className="text-gray-600">Availability Zone:</span>
          <span className="text-gray-900">{agent.az || 'N/A'}</span>
        </div>

        <div className="flex justify-between text-sm">
          <span className="text-gray-600">Current Mode:</span>
          <span className={`badge ${agent.current_mode === 'spot' ? 'badge-success' : 'badge-info'}`}>
            {agent.current_mode || 'N/A'}
          </span>
        </div>

        {agent.last_heartbeat && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-600">Last Heartbeat:</span>
            <span className="text-gray-900">
              {new Date(agent.last_heartbeat).toLocaleString()}
            </span>
          </div>
        )}
      </div>
    </div>
  );
};

export default AgentCard;
