import React from 'react';

const InstanceCard = ({ instance }) => {
  const getModeBadge = (mode) => {
    return mode === 'spot' ? 'badge badge-success' : 'badge badge-info';
  };

  const getStateBadge = (state) => {
    const badges = {
      running: 'badge badge-success',
      stopped: 'badge badge-danger',
      pending: 'badge badge-warning',
      stopping: 'badge badge-warning',
      terminated: 'badge badge-danger'
    };
    return badges[state] || 'badge badge-info';
  };

  return (
    <div className="card hover:shadow-lg transition-shadow duration-200">
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">
            {instance.instance_id}
          </h3>
          <p className="text-sm text-gray-500">
            {instance.instance_type} • {instance.region}
          </p>
        </div>
        <div className="flex gap-2">
          <span className={getModeBadge(instance.mode)}>
            {instance.mode}
          </span>
          <span className={getStateBadge(instance.state)}>
            {instance.state}
          </span>
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-gray-600">Availability Zone:</span>
          <span className="text-gray-900">{instance.az || 'N/A'}</span>
        </div>

        {instance.current_price && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-600">Current Price:</span>
            <span className="text-gray-900 font-semibold">
              ${instance.current_price.toFixed(4)}/hr
            </span>
          </div>
        )}

        {instance.savings_percentage && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-600">Savings:</span>
            <span className="text-green-600 font-semibold">
              {instance.savings_percentage.toFixed(1)}%
            </span>
          </div>
        )}

        {instance.launch_time && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-600">Launch Time:</span>
            <span className="text-gray-900">
              {new Date(instance.launch_time).toLocaleString()}
            </span>
          </div>
        )}
      </div>
    </div>
  );
};

export default InstanceCard;
