import React from 'react';
import { LayoutDashboard, Server, Settings, Activity } from 'lucide-react';

const Sidebar = ({ activeTab, setActiveTab }) => {
  const navigation = [
    { id: 'dashboard', name: 'Dashboard', icon: LayoutDashboard },
    { id: 'agents', name: 'Agents', icon: Server },
    { id: 'activity', name: 'Activity', icon: Activity },
    { id: 'settings', name: 'Settings', icon: Settings },
  ];

  return (
    <aside className="fixed top-0 left-0 h-screen w-64 bg-gradient-to-b from-gray-900 to-gray-800 text-white shadow-2xl overflow-y-auto z-50">
      {/* Header */}
      <div className="p-6 border-b border-gray-700">
        <div className="flex items-center space-x-3">
          <div className="bg-blue-600 p-2 rounded-lg">
            <Server className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-xl font-bold">SpotOptimizer</h1>
            <p className="text-xs text-gray-400">Client Dashboard</p>
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav className="mt-6 px-3">
        {navigation.map((item) => {
          const Icon = item.icon;
          const isActive = activeTab === item.id;

          return (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id)}
              className={`w-full flex items-center space-x-3 px-4 py-3 rounded-lg mb-2 transition-all duration-200 ${
                isActive
                  ? 'bg-blue-600 text-white shadow-lg'
                  : 'text-gray-300 hover:bg-gray-700 hover:text-white'
              }`}
            >
              <Icon className="w-5 h-5" />
              <span className="font-medium">{item.name}</span>
            </button>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="absolute bottom-0 left-0 right-0 p-4 border-t border-gray-700">
        <div className="text-xs text-gray-400 text-center">
          <p>Agent v4.0.0</p>
          <p className="mt-1">© 2025 SpotOptimizer</p>
        </div>
      </div>
    </aside>
  );
};

export default Sidebar;
