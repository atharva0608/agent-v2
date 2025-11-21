# Missing Backend Server Features

This document lists features and API endpoints that need to be implemented in the central backend server for full agent functionality.

## Required API Endpoints

### 1. Agent Termination Notice Handler
**Endpoint:** `POST /api/agents/{agent_id}/termination-imminent`

**Purpose:** Handle spot instance termination notices (2-minute warning)

**Request Body:**
```json
{
    "instance_id": "i-1234567890abcdef0",
    "action": "terminate",
    "time": "2024-01-15T12:30:00Z",
    "detected_at": "2024-01-15T12:28:00Z"
}
```

**Response:**
```json
{
    "success": true,
    "create_emergency_replica": true,
    "target_pool_id": "t3.medium.us-east-1b",
    "instructions": "Create emergency replica and prepare for failover"
}
```

**Implementation Notes:**
- Should trigger emergency replica creation
- Should log system event with severity "warning"
- Should notify relevant stakeholders
- Should update agent status to "terminating"

---

### 2. Rebalance Recommendation Handler
**Endpoint:** `POST /api/agents/{agent_id}/rebalance-recommendation`

**Purpose:** Handle EC2 rebalance recommendations

**Request Body:**
```json
{
    "instance_id": "i-1234567890abcdef0",
    "detected_at": "2024-01-15T12:00:00Z"
}
```

**Response:**
```json
{
    "success": true,
    "action": "switch",
    "target_mode": "spot",
    "target_pool_id": "t3.medium.us-east-1c",
    "reason": "Current pool has elevated interruption risk"
}
```

**Implementation Notes:**
- Should analyze current pool risk
- Should find alternative pools with lower risk
- Can optionally create switch command automatically

---

### 3. Cleanup Report Handler
**Endpoint:** `POST /api/agents/{agent_id}/cleanup-report`

**Purpose:** Receive and log cleanup operation results

**Request Body:**
```json
{
    "timestamp": "2024-01-15T12:00:00Z",
    "snapshots": {
        "type": "snapshots",
        "deleted": ["snap-123", "snap-456"],
        "failed": [],
        "cutoff_date": "2024-01-08T12:00:00Z"
    },
    "amis": {
        "type": "amis",
        "deleted_amis": ["ami-123"],
        "deleted_snapshots": ["snap-789"],
        "failed": [],
        "cutoff_date": "2023-12-16T12:00:00Z"
    }
}
```

**Response:**
```json
{
    "success": true,
    "message": "Cleanup report recorded"
}
```

---

### 4. Client Token Validation
**Endpoint:** `GET /api/client/validate`

**Purpose:** Validate client token for frontend authentication

**Headers:**
```
Authorization: Bearer <client_token>
```

**Response:**
```json
{
    "valid": true,
    "client_id": "uuid-here",
    "name": "Client Name",
    "email": "client@example.com"
}
```

---

### 5. Client Switches History
**Endpoint:** `GET /api/client/{client_id}/switches`

**Purpose:** Get switch history for client dashboard

**Query Parameters:**
- `limit` (optional): Number of records (default: 50)
- `offset` (optional): Pagination offset

**Response:**
```json
{
    "switches": [
        {
            "id": "uuid",
            "agent_id": "uuid",
            "old_instance_id": "i-old",
            "new_instance_id": "i-new",
            "old_mode": "spot",
            "new_mode": "ondemand",
            "old_az": "us-east-1a",
            "new_az": "us-east-1b",
            "trigger_type": "manual",
            "savings_impact": 0.0234,
            "initiated_at": "2024-01-15T12:00:00Z"
        }
    ],
    "total": 100
}
```

---

### 6. Client Savings Data
**Endpoint:** `GET /api/client/{client_id}/savings`

**Purpose:** Get savings statistics for client

**Response:**
```json
{
    "total_savings": 1234.56,
    "monthly_savings": 234.56,
    "savings_by_month": [
        {"month": "2024-01", "savings": 234.56},
        {"month": "2023-12", "savings": 345.67}
    ],
    "average_savings_percent": 62.5
}
```

---

### 7. Emergency Replica Creation
**Endpoint:** `POST /api/agents/{agent_id}/create-emergency-replica`

**Purpose:** Create emergency replica during termination

**Request Body:**
```json
{
    "instance_id": "i-1234567890abcdef0",
    "replica_type": "emergency",
    "parent_instance_id": "i-parent",
    "pool_id": "t3.medium.us-east-1b",
    "status": "ready"
}
```

**Response:**
```json
{
    "success": true,
    "replica_id": "uuid",
    "instance_id": "i-new-replica"
}
```

---

### 8. Replica Termination
**Endpoint:** `DELETE /api/agents/{agent_id}/replicas/{replica_id}`

**Purpose:** Terminate a replica instance

**Response:**
```json
{
    "success": true,
    "message": "Replica terminated"
}
```

---

## Required Database Schema Additions

### 1. cleanup_logs Table
```sql
CREATE TABLE cleanup_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    agent_id VARCHAR(36),
    client_id VARCHAR(36),
    cleanup_type ENUM('snapshots', 'amis', 'full'),
    deleted_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    details JSON,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (agent_id) REFERENCES agents(id),
    FOREIGN KEY (client_id) REFERENCES clients(id)
);
```

### 2. termination_events Table
```sql
CREATE TABLE termination_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    agent_id VARCHAR(36),
    instance_id VARCHAR(50),
    event_type ENUM('termination_notice', 'rebalance_recommendation'),
    action_taken VARCHAR(100),
    emergency_replica_id VARCHAR(36),
    detected_at TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    status ENUM('detected', 'handling', 'resolved', 'failed'),
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);
```

### 3. savings_snapshots Table (for historical tracking)
```sql
CREATE TABLE savings_snapshots (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_id VARCHAR(36),
    snapshot_date DATE,
    total_savings DECIMAL(15, 4),
    spot_hours DECIMAL(10, 2),
    ondemand_hours DECIMAL(10, 2),
    average_savings_percent DECIMAL(5, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY (client_id, snapshot_date),
    FOREIGN KEY (client_id) REFERENCES clients(id)
);
```

### 4. Add columns to agents table
```sql
ALTER TABLE agents ADD COLUMN
    last_termination_notice_at TIMESTAMP NULL,
    last_rebalance_recommendation_at TIMESTAMP NULL,
    emergency_replica_count INT DEFAULT 0;
```

---

## Required Scheduled Jobs

### 1. Daily Savings Calculator
**Frequency:** Daily at midnight

**Purpose:** Calculate and store daily savings for all clients

```python
def calculate_daily_savings():
    # For each client
    # Sum up hourly savings from all switches
    # Store in savings_snapshots table
    pass
```

### 2. Stale Agent Cleanup
**Frequency:** Every 6 hours

**Purpose:** Mark agents as offline if no heartbeat received

```python
def cleanup_stale_agents():
    # Find agents with last_heartbeat_at > AGENT_HEARTBEAT_TIMEOUT
    # Update status to 'offline'
    # Log system event
    pass
```

### 3. Pool Risk Analysis
**Frequency:** Every 15 minutes

**Purpose:** Analyze spot pool interruption risk

```python
def analyze_pool_risk():
    # Fetch spot price history
    # Calculate volatility metrics
    # Update risk_scores table
    # Trigger alerts for high-risk pools
    pass
```

---

## Configuration Requirements

### Environment Variables
```
# Termination handling
TERMINATION_REPLICA_AUTO_CREATE=true
TERMINATION_NOTIFICATION_WEBHOOK=https://hooks.slack.com/...

# Cleanup settings
AUTO_CLEANUP_ENABLED=true
CLEANUP_SNAPSHOTS_DAYS=7
CLEANUP_AMIS_DAYS=30

# Savings calculation
SAVINGS_CALCULATION_HOUR=0  # Midnight
```

---

## Integration Notes

### 1. With Spot Optimizer Agent v4.0.0
The agent now sends requests to:
- `/api/agents/{id}/termination-imminent` - Every 5 seconds when on spot
- `/api/agents/{id}/rebalance-recommendation` - Every 30 seconds when on spot
- `/api/agents/{id}/cleanup-report` - Every hour after cleanup runs

### 2. With Client Dashboard
The dashboard expects:
- `/api/client/validate` - For login authentication
- `/api/client/{id}/switches` - For switch history page
- `/api/client/{id}/savings` - For dashboard stats

### 3. Mutual Exclusivity
When enabling `manual_replica_enabled`:
- Must disable `auto_switch_enabled`
- Must terminate any existing auto-created replicas

When enabling `auto_switch_enabled`:
- Must disable `manual_replica_enabled`
- Must terminate any existing manual replicas
