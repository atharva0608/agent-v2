import React from 'react';

const StatCard = ({ title, value, icon: Icon, trend, trendValue, color = 'blue' }) => {
  const colorClasses = {
    blue: 'border-blue-500 bg-gradient-to-br from-blue-50 to-blue-100',
    green: 'border-green-500 bg-gradient-to-br from-green-50 to-green-100',
    yellow: 'border-yellow-500 bg-gradient-to-br from-yellow-50 to-yellow-100',
    red: 'border-red-500 bg-gradient-to-br from-red-50 to-red-100',
    purple: 'border-purple-500 bg-gradient-to-br from-purple-50 to-purple-100',
  };

  const iconColorClasses = {
    blue: 'bg-blue-500',
    green: 'bg-green-500',
    yellow: 'bg-yellow-500',
    red: 'bg-red-500',
    purple: 'bg-purple-500',
  };

  return (
    <div className={`rounded-xl shadow-lg p-6 border-l-4 ${colorClasses[color]} hover:shadow-xl transition-shadow duration-200`}>
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <p className="text-sm font-medium text-gray-600 uppercase tracking-wide">{title}</p>
          <p className="text-3xl font-bold text-gray-900 mt-2">{value}</p>
          {trend && (
            <p className={`text-sm mt-2 ${trend === 'up' ? 'text-green-600' : trend === 'down' ? 'text-red-600' : 'text-gray-600'}`}>
              {trend === 'up' ? '↑' : trend === 'down' ? '↓' : '→'} {trendValue}
            </p>
          )}
        </div>
        {Icon && (
          <div className={`p-4 ${iconColorClasses[color]} rounded-xl`}>
            <Icon className="w-8 h-8 text-white" />
          </div>
        )}
      </div>
    </div>
  );
};

export default StatCard;
