# Quick Upgrade Guide: Agent-v2 → Final-ML Backend Integration

This guide provides step-by-step instructions to integrate your agent-v2 deployment with the complete final-ml backend.

## Prerequisites

- MySQL 8.0+ database server
- Python 3.8+ with pip
- Access to agent-v2 repository (current setup)
- Access to final-ml repository

---

## Step 1: Database Setup

### 1.1 Create Database

```bash
# Connect to MySQL
mysql -u root -p

# Create database
CREATE DATABASE spot_optimizer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

# Create user
CREATE USER 'spot_user'@'localhost' IDENTIFIED BY 'your-secure-password';
GRANT ALL PRIVILEGES ON spot_optimizer.* TO 'spot_user'@'localhost';
FLUSH PRIVILEGES;

# Exit MySQL
EXIT;
```

### 1.2 Load Schema

```bash
# Navigate to final-ml repository
cd /home/user/final-ml-reference

# Import complete schema
mysql -u spot_user -p spot_optimizer < database/schema.sql

# Verify tables created
mysql -u spot_user -p spot_optimizer -e "SHOW TABLES;"
```

Expected output: 40+ tables including `agents`, `clients`, `commands`, `replicas`, etc.

### 1.3 Create Initial Client

```bash
# Generate a secure client token
CLIENT_TOKEN=$(openssl rand -hex 32)

# Insert client record
mysql -u spot_user -p spot_optimizer <<EOF
INSERT INTO clients (id, name, email, client_token, plan, max_agents, max_instances, is_active)
VALUES (UUID(), 'Production Client', 'admin@example.com', '${CLIENT_TOKEN}', 'pro', 50, 100, TRUE);
EOF

# Display the token (save this!)
echo "CLIENT_TOKEN=${CLIENT_TOKEN}"
```

**IMPORTANT:** Save the `CLIENT_TOKEN` - you'll need it for agent configuration.

---

## Step 2: Backend Deployment

### 2.1 Install Dependencies

```bash
cd /home/user/final-ml-reference/backend

# Install Python dependencies
pip3 install flask flask-cors pymysql requests schedule apscheduler marshmallow
```

### 2.2 Create Environment Configuration

```bash
cat > /home/user/final-ml-reference/backend/.env <<'EOF'
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=spot_optimizer
DB_USER=spot_user
DB_PASSWORD=your-secure-password

# Server Configuration
FLASK_ENV=production
FLASK_APP=backend.py
PORT=5000
HOST=0.0.0.0

# Security
SECRET_KEY=your-secret-key-here
CORS_ORIGINS=*

# Decision Engine
DECISION_ENGINE_CLASS=decision_engines.ml_based_engine.MLBasedDecisionEngine
ML_MODELS_DIR=./models

# Features
ENABLE_SEF=true
ENABLE_ML_DECISIONS=false
ENABLE_BACKGROUND_JOBS=true

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/spot-optimizer-backend/backend.log
EOF

# Replace placeholder values
nano /home/user/final-ml-reference/backend/.env
```

### 2.3 Create Systemd Service

```bash
sudo tee /etc/systemd/system/spot-optimizer-backend.service <<'EOF'
[Unit]
Description=AWS Spot Optimizer Backend API
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/user/final-ml-reference/backend
Environment="PYTHONUNBUFFERED=1"
EnvironmentFile=/home/user/final-ml-reference/backend/.env
ExecStart=/usr/bin/python3 backend.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/spot-optimizer-backend/backend.log
StandardError=append:/var/log/spot-optimizer-backend/backend-error.log

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
sudo mkdir -p /var/log/spot-optimizer-backend
sudo chown ubuntu:ubuntu /var/log/spot-optimizer-backend

# Reload systemd
sudo systemctl daemon-reload

# Enable and start service
sudo systemctl enable spot-optimizer-backend
sudo systemctl start spot-optimizer-backend

# Check status
sudo systemctl status spot-optimizer-backend
```

### 2.4 Verify Backend is Running

```bash
# Check backend health
curl http://localhost:5000/health

# Expected output:
# {"status":"ok","backend":"...","token_configured":true}

# Test agent registration endpoint
curl -X POST http://localhost:5000/api/agents/register \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${CLIENT_TOKEN}" \
  -d '{
    "client_token": "'${CLIENT_TOKEN}'",
    "logical_agent_id": "test-agent",
    "hostname": "test-host",
    "instance_id": "i-test123",
    "instance_type": "t3.medium",
    "region": "us-east-1",
    "az": "us-east-1a",
    "ami_id": "ami-test",
    "mode": "ondemand",
    "agent_version": "4.0.0",
    "private_ip": "10.0.1.100",
    "public_ip": "54.1.2.3"
  }'
```

---

## Step 3: Update Agent Configuration

### 3.1 Update Agent Environment File

```bash
# SSH to your agent instance
ssh ubuntu@your-agent-instance

# Edit agent configuration
sudo nano /etc/spot-optimizer/agent.env
```

Update the following variables:

```bash
# Point to your new backend (use actual IP/hostname)
SPOT_OPTIMIZER_SERVER_URL=http://your-backend-server:5000

# Use the client token you generated
SPOT_OPTIMIZER_CLIENT_TOKEN=your-client-token-here

# Set a unique logical agent ID
LOGICAL_AGENT_ID=my-production-server-01

# AWS Configuration
AWS_REGION=us-east-1

# Timing Configuration (optional, these are defaults)
HEARTBEAT_INTERVAL=30
PENDING_COMMANDS_CHECK_INTERVAL=15
PRICING_REPORT_INTERVAL=300
TERMINATION_CHECK_INTERVAL=5

# Switch Configuration
AUTO_TERMINATE_OLD_INSTANCE=true
TERMINATE_WAIT_TIME=300

# Cleanup Configuration
CLEANUP_SNAPSHOTS_OLDER_THAN_DAYS=7
CLEANUP_AMIS_OLDER_THAN_DAYS=30

# Replica Configuration (optional)
REPLICA_ENABLED=false
REPLICA_COUNT=1
```

### 3.2 Restart Agent

```bash
# Restart the agent service
sudo systemctl restart spot-optimizer-agent

# Check status
sudo systemctl status spot-optimizer-agent

# Watch logs
tail -f /var/log/spot-optimizer/agent-error.log
```

**Expected Log Output:**
```
INFO - ================================================================================
INFO - Agent started - ID: <agent-uuid>
INFO - Instance: <instance-id> (t3.medium)
INFO - Version: 4.0.0
INFO - ================================================================================
INFO - Registered as agent: <agent-uuid>
INFO - Started worker: Heartbeat
INFO - Started worker: PricingReport
INFO - Heartbeat sent successfully
```

---

## Step 4: Update API Proxy (Optional)

If you're using the agent-v2 API proxy for the dashboard:

### 4.1 Update Proxy Configuration

```bash
cd /home/user/agent-v2/frontend

# Edit API server configuration
nano api_server.py
```

Update line 16:
```python
BACKEND_URL = os.getenv('BACKEND_URL', 'http://your-backend-server:5000')
```

### 4.2 Restart API Proxy

```bash
# If using systemd
sudo systemctl restart spot-optimizer-api-server

# Or if running manually
pkill -f api_server.py
cd /home/user/agent-v2/frontend
python3 api_server.py &
```

---

## Step 5: Verification

### 5.1 Check Agent Registration

```bash
# Query database for agent
mysql -u spot_user -p spot_optimizer <<EOF
SELECT
    id, logical_agent_id, instance_id, instance_type,
    status, last_heartbeat_at, agent_version
FROM agents
ORDER BY created_at DESC
LIMIT 5;
EOF
```

### 5.2 Check Heartbeats

```bash
# Watch for heartbeat updates
watch -n 5 'mysql -u spot_user -p"your-password" spot_optimizer -e "
SELECT
    logical_agent_id,
    status,
    last_heartbeat_at,
    TIMESTAMPDIFF(SECOND, last_heartbeat_at, NOW()) AS seconds_ago
FROM agents
ORDER BY last_heartbeat_at DESC
LIMIT 5;"'
```

Expected: `seconds_ago` should stay < 60 seconds

### 5.3 Check Pricing Reports

```bash
# Wait 5 minutes, then check
mysql -u spot_user -p spot_optimizer <<EOF
SELECT
    agent_id,
    instance_type,
    current_mode,
    on_demand_price,
    current_spot_price,
    received_at
FROM pricing_reports
ORDER BY received_at DESC
LIMIT 5;
EOF
```

### 5.4 Test Dashboard (if using proxy)

```bash
# Get all agents
curl http://localhost:5000/api/agents

# Get agent stats
curl http://localhost:5000/api/agents/stats

# Get savings
curl http://localhost:5000/api/stats/savings
```

---

## Step 6: Enable Advanced Features

### 6.1 Enable Replica Management

```bash
# Update agent configuration
ssh ubuntu@your-agent-instance
sudo nano /etc/spot-optimizer/agent.env

# Add/update:
REPLICA_ENABLED=true
REPLICA_COUNT=1
MANUAL_REPLICA_ENABLED=false

# Restart agent
sudo systemctl restart spot-optimizer-agent
```

### 6.2 Enable Smart Emergency Fallback

Already enabled in backend by default. Verify:

```bash
# Check backend logs
sudo tail -f /var/log/spot-optimizer-backend/backend.log | grep SEF
```

### 6.3 Upload ML Models (Optional)

```bash
# Create models directory
mkdir -p /home/user/final-ml-reference/backend/models

# Upload your models (.pkl, .h5, .pth, .onnx)
# Use the admin API endpoint:

curl -X POST http://your-backend:5000/api/admin/ml-models/upload \
  -H "Authorization: Bearer admin-token" \
  -F "file=@your-model.pkl"

# Activate model
curl -X POST http://your-backend:5000/api/admin/ml-models/activate \
  -H "Authorization: Bearer admin-token" \
  -d '{"model_id": "model-uuid-here"}'

# Enable ML decisions in backend .env
ENABLE_ML_DECISIONS=true
```

---

## Troubleshooting

### Agent Can't Connect to Backend

**Check 1: Network connectivity**
```bash
# From agent instance
curl -v http://your-backend:5000/health
```

**Check 2: Firewall rules**
```bash
# On backend server
sudo ufw status
sudo ufw allow 5000/tcp
```

**Check 3: Backend is running**
```bash
sudo systemctl status spot-optimizer-backend
sudo journalctl -u spot-optimizer-backend -f
```

### Agent Logs Show "Invalid client token"

```bash
# Verify token in database
mysql -u spot_user -p spot_optimizer <<EOF
SELECT name, client_token, is_active FROM clients;
EOF

# Update agent configuration with correct token
sudo nano /etc/spot-optimizer/agent.env
sudo systemctl restart spot-optimizer-agent
```

### Dashboard Shows No Data

**Check 1: API proxy configuration**
```bash
# Verify BACKEND_URL points to backend
cat /home/user/agent-v2/frontend/api_server.py | grep BACKEND_URL
```

**Check 2: Backend endpoints**
```bash
# Test directly
curl http://your-backend:5000/api/agents
```

**Check 3: Database has data**
```bash
mysql -u spot_user -p spot_optimizer -e "SELECT COUNT(*) FROM agents;"
```

### Database Connection Errors

```bash
# Test connection
mysql -u spot_user -p -h localhost spot_optimizer -e "SELECT 1;"

# Check backend configuration
cat /home/user/final-ml-reference/backend/.env | grep DB_

# Check MySQL is running
sudo systemctl status mysql
```

---

## Performance Tuning

### Database Optimization

```bash
# Add indexes for frequently queried columns
mysql -u spot_user -p spot_optimizer <<'EOF'
-- Already included in schema, but verify:
SHOW INDEX FROM agents;
SHOW INDEX FROM pricing_reports;
SHOW INDEX FROM switches;
EOF
```

### Backend Scaling

For high-traffic deployments:

```bash
# Use gunicorn instead of Flask dev server
pip3 install gunicorn

# Update systemd service
sudo nano /etc/systemd/system/spot-optimizer-backend.service

# Change ExecStart to:
ExecStart=/usr/bin/gunicorn -w 4 -b 0.0.0.0:5000 backend:app

# Restart
sudo systemctl restart spot-optimizer-backend
```

---

## Monitoring

### Set Up Log Rotation

```bash
sudo tee /etc/logrotate.d/spot-optimizer <<'EOF'
/var/log/spot-optimizer/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    missingok
    create 0644 ubuntu ubuntu
}

/var/log/spot-optimizer-backend/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    missingok
    create 0644 ubuntu ubuntu
}
EOF
```

### Set Up Monitoring Alerts

```bash
# Example: Alert when agent goes offline
mysql -u spot_user -p spot_optimizer <<'EOF'
CREATE EVENT IF NOT EXISTS evt_alert_offline_agents
ON SCHEDULE EVERY 5 MINUTE
DO
  INSERT INTO notifications (client_id, notification_type, title, message, severity)
  SELECT
    a.client_id,
    'agent_offline',
    CONCAT('Agent ', a.logical_agent_id, ' is offline'),
    CONCAT('Agent has not sent heartbeat for ',
           TIMESTAMPDIFF(MINUTE, a.last_heartbeat_at, NOW()), ' minutes'),
    'warning'
  FROM agents a
  WHERE a.status = 'offline'
    AND a.last_heartbeat_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.agent_id = a.id
        AND n.notification_type = 'agent_offline'
        AND n.created_at > DATE_SUB(NOW(), INTERVAL 30 MINUTE)
    );
EOF
```

---

## Backup & Recovery

### Database Backup

```bash
# Create backup script
cat > /home/user/backup-spot-optimizer.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/spot-optimizer"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

mysqldump -u spot_user -p'your-password' spot_optimizer \
  --single-transaction \
  --quick \
  --lock-tables=false \
  > $BACKUP_DIR/spot_optimizer_$DATE.sql

# Keep last 7 days
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
EOF

chmod +x /home/user/backup-spot-optimizer.sh

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /home/user/backup-spot-optimizer.sh") | crontab -
```

---

## Next Steps

After completing this upgrade:

1. **Monitor for 24 hours** to ensure stability
2. **Test switch operations** manually
3. **Enable replica management** if needed
4. **Set up monitoring and alerting**
5. **Train ML models** on your data (optional)
6. **Configure automatic switching** based on your preferences

---

## Rollback Plan

If you need to rollback:

1. **Stop new backend:**
   ```bash
   sudo systemctl stop spot-optimizer-backend
   ```

2. **Revert agent configuration:**
   ```bash
   sudo nano /etc/spot-optimizer/agent.env
   # Change SPOT_OPTIMIZER_SERVER_URL back to old value
   sudo systemctl restart spot-optimizer-agent
   ```

3. **Revert API proxy:**
   ```bash
   nano /home/user/agent-v2/frontend/api_server.py
   # Change BACKEND_URL back
   sudo systemctl restart spot-optimizer-api-server
   ```

---

## Support

For issues during upgrade:

1. Check logs:
   - Agent: `/var/log/spot-optimizer/agent-error.log`
   - Backend: `/var/log/spot-optimizer-backend/backend-error.log`
   - MySQL: `/var/log/mysql/error.log`

2. Verify connectivity:
   ```bash
   # From agent to backend
   curl -v http://backend:5000/health

   # From backend to database
   mysql -u spot_user -p spot_optimizer -e "SELECT 1;"
   ```

3. Check systemd services:
   ```bash
   sudo systemctl status spot-optimizer-agent
   sudo systemctl status spot-optimizer-backend
   sudo systemctl status mysql
   ```

---

**Upgrade completed?** Verify everything is working in [Step 5: Verification](#step-5-verification)
