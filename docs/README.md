# AWS Spot Optimizer

A complete solution for optimizing AWS EC2 costs through intelligent spot instance management.

## Overview

AWS Spot Optimizer automatically manages your EC2 instances to maximize cost savings by:
- Switching between spot and on-demand instances based on pricing
- Handling spot interruption notices gracefully
- Managing replica instances for high availability
- Cleaning up old snapshots and AMIs automatically

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Central Server                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
│  │   Flask     │  │   MySQL     │  │  ML Model   │  │  Scheduler  │   │
│  │   API       │  │   Database  │  │  Engine     │  │  Jobs       │   │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Client Instances                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Spot Optimizer Agent                          │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐            │   │
│  │  │Heartbeat│  │ Pricing │  │ Command │  │ Cleanup │            │   │
│  │  │ Worker  │  │ Worker  │  │ Worker  │  │ Worker  │            │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘            │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                         │   │
│  │  │Termination│ │Rebalance│  │ Replica │                         │   │
│  │  │ Monitor  │  │ Monitor │  │ Manager │                         │   │
│  │  └─────────┘  └─────────┘  └─────────┘                         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
agent-v2/
├── backend/                    # Agent backend code
│   ├── spot_optimizer_agent.py # Main production agent v4.0.0
│   └── spot_agent_production_v2_final.py  # Legacy agent
│
├── frontend/                   # Client dashboard
│   ├── app.py                  # Flask application
│   ├── requirements.txt        # Python dependencies
│   ├── static/                 # Static assets
│   └── templates/              # HTML templates
│       ├── base.html           # Base template
│       ├── login.html          # Login page
│       ├── dashboard.html      # Main dashboard
│       ├── agents.html         # Agents management
│       ├── instances.html      # Instances view
│       ├── switches.html       # Switch history
│       ├── replicas.html       # Replica management
│       └── settings.html       # Settings page
│
├── docs/                       # Documentation
│   ├── README.md               # This file
│   ├── PROBLEMS.md             # Known issues and solutions
│   ├── iam-policy.json         # IAM policy for client instances
│   └── iam-trust-policy.json   # Trust policy for IAM role
│
├── scripts/                    # Setup and utility scripts
│   ├── setup.sh                # Agent installation script
│   ├── cleanup.sh              # Manual cleanup script
│   └── uninstall.sh            # Agent uninstall script
│
└── missing-backend-server/     # Backend requirements documentation
    ├── MISSING_FEATURES.md     # Required API endpoints
    └── REQUIRED_SCHEMA.sql     # Required database schema
```

## Quick Start

### 1. Set Up Central Server

Deploy the central server from [final-ml repository](https://github.com/atharva0608/final-ml):

```bash
git clone https://github.com/atharva0608/final-ml.git
cd final-ml/backend
pip install -r requirements.txt
python backend.py
```

### 2. Create IAM Role

Create an IAM role for your EC2 instances using the policy in `docs/iam-policy.json`:

```bash
# Create the role
aws iam create-role \
    --role-name SpotOptimizerAgentRole \
    --assume-role-policy-document file://docs/iam-trust-policy.json

# Attach the policy
aws iam put-role-policy \
    --role-name SpotOptimizerAgentRole \
    --policy-name SpotOptimizerPolicy \
    --policy-document file://docs/iam-policy.json

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name SpotOptimizerAgentProfile

# Add role to profile
aws iam add-role-to-instance-profile \
    --instance-profile-name SpotOptimizerAgentProfile \
    --role-name SpotOptimizerAgentRole
```

### 3. Install Agent on EC2 Instance

SSH into your EC2 instance and run:

```bash
# Clone the repository
git clone https://github.com/atharva0608/agent-v2.git
cd agent-v2/scripts

# Run setup script
chmod +x setup.sh
./setup.sh
```

You'll be prompted for:
- Central Server URL
- Client Token (from admin dashboard)
- AWS Region

### 4. Start Client Dashboard (Optional)

```bash
cd frontend
pip install -r requirements.txt
python app.py
```

Access at `http://localhost:3000`

## Agent Features

### Core Features

| Feature | Description |
|---------|-------------|
| **Instance Switching** | Seamlessly switch between spot and on-demand |
| **Dual Mode Detection** | Verify instance mode via API + metadata |
| **Priority Commands** | Execute high-priority commands first |
| **Graceful Shutdown** | Clean shutdown with thread cleanup |

### Advanced Features

| Feature | Description |
|---------|-------------|
| **Termination Handling** | Detect and respond to 2-minute warnings |
| **Rebalance Detection** | Monitor EC2 rebalance recommendations |
| **Replica Management** | Create/manage emergency and manual replicas |
| **Auto Cleanup** | Clean old snapshots and AMIs automatically |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SPOT_OPTIMIZER_SERVER_URL` | `http://localhost:5000` | Central server URL |
| `SPOT_OPTIMIZER_CLIENT_TOKEN` | Required | Client authentication token |
| `AWS_REGION` | `us-east-1` | AWS region |
| `LOGICAL_AGENT_ID` | Instance ID | Persistent agent identifier |
| `HEARTBEAT_INTERVAL` | 30 | Heartbeat interval (seconds) |
| `PENDING_COMMANDS_CHECK_INTERVAL` | 15 | Command polling interval |
| `AUTO_TERMINATE_OLD_INSTANCE` | true | Auto-terminate after switch |
| `CREATE_SNAPSHOT_ON_SWITCH` | true | Create AMI before switch |
| `CLEANUP_SNAPSHOTS_OLDER_THAN_DAYS` | 7 | Snapshot retention days |
| `CLEANUP_AMIS_OLDER_THAN_DAYS` | 30 | AMI retention days |

### Configuration File

Located at `/etc/spot-optimizer/agent.env`:

```env
SPOT_OPTIMIZER_SERVER_URL=https://api.example.com
SPOT_OPTIMIZER_CLIENT_TOKEN=your-token-here
AWS_REGION=us-east-1
LOGICAL_AGENT_ID=my-agent-1
```

## Management Commands

```bash
# Check agent status
spot-agent-status

# View live logs
spot-agent-logs

# Restart agent
spot-agent-restart

# Manual cleanup (dry run)
./scripts/cleanup.sh --region us-east-1

# Execute cleanup
./scripts/cleanup.sh --region us-east-1 --execute

# Uninstall agent
./scripts/uninstall.sh
```

## API Reference

### Agent Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/agents/register` | POST | Register new agent |
| `/api/agents/{id}/heartbeat` | POST | Send heartbeat |
| `/api/agents/{id}/config` | GET | Get agent config |
| `/api/agents/{id}/pending-commands` | GET | Get pending commands |
| `/api/agents/{id}/pricing-report` | POST | Submit pricing data |
| `/api/agents/{id}/switch-report` | POST | Report switch result |
| `/api/agents/{id}/termination-imminent` | POST | Report termination notice |

### Client Dashboard Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/dashboard/stats` | GET | Dashboard statistics |
| `/api/agents` | GET | List all agents |
| `/api/agents/{id}/toggle-enabled` | POST | Enable/disable agent |
| `/api/agents/{id}/switch` | POST | Trigger manual switch |
| `/api/replicas` | GET | List all replicas |

## Troubleshooting

See [PROBLEMS.md](PROBLEMS.md) for common issues and solutions.

### Quick Checks

```bash
# Check agent is running
systemctl status spot-optimizer-agent

# Check recent logs
tail -50 /var/log/spot-optimizer/agent.log

# Test server connectivity
curl -s https://your-server/health

# Verify AWS credentials
aws sts get-caller-identity
```

## License

MIT License - See LICENSE file for details.
