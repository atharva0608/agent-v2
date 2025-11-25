import React from 'react';
import { Settings, Server, Info } from 'lucide-react';

const SettingsPage = () => {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-3xl font-bold text-gray-900">Settings</h2>
        <p className="text-gray-600 mt-1">Agent configuration and system info</p>
      </div>

      <div className="bg-white rounded-xl shadow-lg p-6">
        <div className="flex items-center space-x-3 mb-6">
          <Info className="w-6 h-6 text-blue-600" />
          <h3 className="text-xl font-semibold">System Information</h3>
        </div>

        <div className="space-y-4">
          <div className="flex justify-between py-3 border-b">
            <span className="text-gray-600">Agent Version</span>
            <span className="font-medium">4.0.0</span>
          </div>
          <div className="flex justify-between py-3 border-b">
            <span className="text-gray-600">Backend URL</span>
            <span className="font-medium">{window.location.origin}</span>
          </div>
          <div className="flex justify-between py-3 border-b">
            <span className="text-gray-600">Dashboard</span>
            <span className="font-medium text-green-600">Active</span>
          </div>
        </div>
      </div>

      <div className="bg-blue-50 border-l-4 border-blue-500 p-6 rounded-lg">
        <div className="flex items-start space-x-3">
          <Server className="w-5 h-5 text-blue-600 mt-0.5" />
          <div>
            <h4 className="font-semibold text-blue-900 mb-1">Agent Configuration</h4>
            <p className="text-sm text-blue-800">
              Agent settings are managed through the configuration file at <code className="bg-blue-100 px-2 py-0.5 rounded">/etc/spot-optimizer/agent.env</code>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SettingsPage;
