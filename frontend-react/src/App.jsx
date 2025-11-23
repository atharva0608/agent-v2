import React, { useState } from 'react';
import Sidebar from './components/layout/Sidebar';
import Dashboard from './pages/Dashboard';
import AgentsPage from './pages/AgentsPage';
import SettingsPage from './pages/SettingsPage';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');

  const renderPage = () => {
    switch (activeTab) {
      case 'dashboard':
        return <Dashboard />;
      case 'agents':
        return <AgentsPage />;
      case 'activity':
        return <Dashboard />; // Reuse dashboard for now
      case 'settings':
        return <SettingsPage />;
      default:
        return <Dashboard />;
    }
  };

  return (
    <div className="flex h-screen bg-gray-50">
      <Sidebar activeTab={activeTab} setActiveTab={setActiveTab} />

      <main className="ml-64 flex-1 overflow-y-auto">
        <div className="container mx-auto px-6 py-8">
          {renderPage()}
        </div>
      </main>
    </div>
  );
}

export default App;
