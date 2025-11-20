# Client Agent & Frontend

This directory contains the supportive client agent backend and client-centric frontend for the Spot Optimizer system.

## Overview

The client agent system consists of two main components:

1. **Client Agent Backend** (`client_agent.py`) - A lightweight Python agent that communicates with the central server
2. **Client Frontend** (`client-frontend/`) - A React-based web dashboard showing client-specific information

## Architecture

```
┌─────────────────────────────────────┐
│   Central Server                    │
│   (https://github.com/              │
│    atharva0608/final-ml.git)        │
└────────────┬────────────────────────┘
             │ HTTP/HTTPS API
             │
    ┌────────┴────────┐
    │                 │
┌───▼──────────┐  ┌──▼────────────────┐
│ Client Agent │  │ Client Frontend   │
│ Backend      │  │ (Port 80)         │
│              │  │                   │
│ • Fetches    │  │ • Shows client    │
│   data       │  │   info only       │
│ • Executes   │  │ • Auto-refresh    │
│   switches   │  │ • Real-time data  │
│ • Fast       │  │                   │
│   polling    │  │                   │
└──────────────┘  └───────────────────┘
```

## Features

### Client Agent Backend

- **Fast Data Fetching**: Polls central server every 15 seconds
- **Quick Switch Execution**: Checks for pending switches every 5 seconds
- **Supports Manual & Model-Driven Switches**: Executes both types of switches
- **Real-time Status Updates**: Sends heartbeat every 10 seconds
- **Minimal Overhead**: Lightweight design for minimal resource usage
- **Automatic Retry**: Handles connection failures gracefully

### Client Frontend

- **Client-Centric Dashboard**: Shows only information relevant to the specific client
- **Real-time Updates**: Auto-refreshes data every 15 seconds
- **Clean UI**: Built with React and Tailwind CSS (similar to admin dashboard)
- **Port 80**: Runs on standard HTTP port for easy access
- **Responsive Design**: Works on desktop and mobile devices
- **Statistics Overview**: Shows agents, instances, and savings at a glance

## Installation

### Prerequisites

- **For Backend**: Python 3.7+, pip
- **For Frontend**: Node.js 18+, npm

### Quick Start

#### 1. Install Client Agent Backend

```bash
chmod +x setup_client_agent.sh
./setup_client_agent.sh
```

You'll be prompted for:
- Central Server URL (e.g., `http://your-server.com:5000`)
- Client Token (authentication token)
- Client ID (your client identifier)

#### 2. Install Client Frontend

```bash
chmod +x setup_client_frontend.sh
sudo ./setup_client_frontend.sh
```

You'll be prompted for the same configuration as above.

**Note**: Port 80 requires root privileges, hence `sudo`.

## Configuration

### Backend Configuration

Edit `/etc/client-agent/.env`:

```bash
# Central Server URL
CENTRAL_SERVER_URL=http://localhost:5000

# Client Authentication
CLIENT_TOKEN=your_token_here
CLIENT_ID=your_client_id

# Timing Configuration (seconds)
STATUS_UPDATE_INTERVAL=10
DATA_FETCH_INTERVAL=15
SWITCH_CHECK_INTERVAL=5
```

### Frontend Configuration

Edit `client-frontend/.env`:

```bash
VITE_CENTRAL_SERVER_URL=http://localhost:5000
VITE_CLIENT_TOKEN=your_token_here
VITE_CLIENT_ID=your_client_id
```

## Usage

### Client Agent Backend

```bash
# Check status
client-agent-status

# View logs
client-agent-logs

# Restart agent
client-agent-restart

# Manual control
sudo systemctl start client-agent
sudo systemctl stop client-agent
sudo systemctl restart client-agent
```

### Client Frontend

```bash
# Check status
client-frontend-status

# View logs
client-frontend-logs

# Restart frontend
client-frontend-restart

# Development mode
cd client-frontend
sudo npm run dev

# Build for production
npm run build
```

Access the dashboard at:
- `http://localhost` (local)
- `http://<your-server-ip>` (remote)

## API Endpoints

The client agent communicates with these central server endpoints:

### Client Information
- `GET /api/clients/{client_id}` - Get client info
- `POST /api/clients/{client_id}/agent-status` - Update agent status

### Agents & Instances
- `GET /api/clients/{client_id}/agents` - Get all agents
- `GET /api/clients/{client_id}/instances` - Get all instances

### Savings & Statistics
- `GET /api/clients/{client_id}/savings` - Get savings data
- `GET /api/clients/{client_id}/stats` - Get statistics

### Switch Operations
- `GET /api/clients/{client_id}/pending-switches` - Get pending switches
- `POST /api/clients/{client_id}/execute-switch` - Execute a switch

## Dashboard Features

The client frontend displays:

1. **Overview Statistics**
   - Active agents count
   - Running instances count
   - Spot vs on-demand breakdown
   - Total savings amount and percentage

2. **Agents Section**
   - List of all agents for this client
   - Status (online/offline/disabled)
   - Instance details
   - Last heartbeat time

3. **Instances Section**
   - All instances managed by client
   - Instance type and region
   - Current mode (spot/on-demand)
   - Pricing information
   - Savings percentage

4. **Auto-Refresh**
   - Automatic data refresh every 15 seconds
   - Manual refresh button

## Development

### Backend Development

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install requests python-dotenv

# Run agent
python client_agent.py
```

### Frontend Development

```bash
cd client-frontend

# Install dependencies
npm install

# Run development server (port 80)
sudo npm run dev

# Build for production
npm run build

# Preview production build
sudo npm run preview
```

## Troubleshooting

### Backend Issues

**Agent won't start:**
```bash
# Check logs
client-agent-logs

# Check service status
sudo systemctl status client-agent

# Verify configuration
cat /etc/client-agent/.env
```

**Connection errors:**
- Verify `CENTRAL_SERVER_URL` is correct
- Check network connectivity
- Verify `CLIENT_TOKEN` is valid
- Ensure firewall allows outbound connections

### Frontend Issues

**Frontend won't start on port 80:**
```bash
# Check if port is in use
sudo lsof -i :80

# Run on different port (edit vite.config.js)
# Or use reverse proxy (nginx/apache)
```

**Data not loading:**
- Check browser console for errors
- Verify `.env` file exists and has correct values
- Ensure central server is accessible
- Check CORS settings on central server

## Logs

### Backend Logs
- Service logs: `/var/log/client-agent/client_agent.log`
- View live: `client-agent-logs`

### Frontend Logs
- Service logs: `/var/log/client-frontend.log`
- View live: `client-frontend-logs`
- Browser console: Press F12 in browser

## Security Notes

1. **Tokens**: Keep `CLIENT_TOKEN` secure - it provides full access to client data
2. **Port 80**: Frontend runs as root to bind to port 80. Consider using nginx as reverse proxy for production
3. **HTTPS**: For production, use HTTPS for both backend and frontend
4. **Firewall**: Only expose port 80 if needed externally

## Integration with Central Server

This client agent expects the central server to implement the API endpoints listed above.

The central server repository is at:
- **Backend**: https://github.com/atharva0608/final-ml.git
- **Frontend**: https://github.com/atharva0608/frontend-.git

Ensure your central server has the necessary endpoints before deploying the client agent.

## Performance

### Backend Agent
- **Memory Usage**: ~30-50 MB
- **CPU Usage**: <1% (idle), 5-10% (active)
- **Network**: Minimal (API calls every 5-15 seconds)

### Frontend
- **Initial Load**: ~2-3 MB
- **Memory**: ~50-100 MB (browser)
- **Network**: ~10-20 KB per refresh

## License

Same as parent project.

## Support

For issues or questions:
1. Check logs first
2. Verify configuration
3. Test central server connectivity
4. Review this README

## Version

- **Client Agent Backend**: v1.0.0
- **Client Frontend**: v1.0.0
