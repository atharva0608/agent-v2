# Deployment Instructions - Agent Termination Fix

## Summary of Changes

This update fixes replica and instance termination issues by syncing the agent with the central backend and implementing proper AWS EC2 termination workflows.

---

## AGENT CHANGES (Already Complete ✓)

### 1. Added Replica Termination Worker
**File**: `backend/spot_optimizer_agent.py`
**Lines**: 1780-2001

**What it does**:
- Polls backend every 30 seconds for replicas with `status='terminated'`
- Terminates EC2 instances when user turns OFF manual replica toggle
- Reports termination results back to backend
- Comprehensive logging with visual indicators

**Key Features**:
- Checks instance exists before terminating (handles already-terminated gracefully)
- Updates backend database after successful termination
- Error handling for AWS API failures

### 2. Enhanced Cleanup Worker with Instance Termination
**File**: `backend/spot_optimizer_agent.py`
**Lines**: 2244-2475

**What it does**:
- Polls backend every 60 seconds for zombie/terminated instances
- Terminates instances marked for deletion in database
- Reports results to backend for tracking
- Respects auto-terminate enabled/disabled setting

**Key Features**:
- Separate from AMI/snapshot cleanup (which runs every hour)
- Handles InvalidInstanceID.NotFound errors gracefully
- Updates database with termination timestamps
- Prevents duplicate termination attempts

### 3. Added Backend API Methods
**File**: `backend/spot_optimizer_agent.py`
**Lines**: 419-455

**New Methods**:
```python
def get_instances_to_terminate(self, agent_id: str) -> Optional[Dict]
def report_instance_termination(self, agent_id: str, instance_id: str, success: bool, ...)
```

### 4. Enhanced Logging Throughout
- Visual indicators: 🔴 🔄 🔧 ✅ ✗ ⚠️
- Structured output for all operations
- Clear success/failure markers
- Auto-terminate status logging

---

## BACKEND CHANGES REQUIRED

### 1. Database Schema Migration

**File**: `database/migrations/add_termination_tracking.sql`

**What it adds**:
```sql
-- Add to instances table
ALTER TABLE instances
    ADD COLUMN IF NOT EXISTS termination_attempted_at TIMESTAMP NULL
        COMMENT 'When agent last attempted to terminate this instance',
    ADD COLUMN IF NOT EXISTS termination_confirmed BOOLEAN DEFAULT FALSE
        COMMENT 'TRUE if AWS confirmed termination';

-- Add to replica_instances table
ALTER TABLE replica_instances
    ADD COLUMN IF NOT EXISTS termination_attempted_at TIMESTAMP NULL
        COMMENT 'When agent last attempted to terminate this instance',
    ADD COLUMN IF NOT EXISTS termination_confirmed BOOLEAN DEFAULT FALSE
        COMMENT 'TRUE if AWS confirmed termination';

-- Add indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_instances_zombie_termination
    ON instances(instance_status, termination_attempted_at, region);

CREATE INDEX IF NOT EXISTS idx_replicas_termination
    ON replica_instances(status, termination_attempted_at, agent_id);
```

**Why needed**:
- Tracks termination attempts to prevent duplicates
- Backend queries these columns to avoid re-attempting within 5 minutes
- Stores AWS termination confirmation status
- Indexes improve query performance

### 2. Backend Endpoints (Already in final-ml)

These endpoints are already implemented in the final-ml repository branch `claude/fix-manual-controls-visibility-0126jMKyCBaNmA1dFEPQ2ePU`:

**GET `/api/agents/{agent_id}/instances-to-terminate`**
- Returns list of instances marked as 'zombie' or 'terminated'
- Filters out recently attempted terminations (< 5 minutes)
- Used by cleanup worker

**POST `/api/agents/{agent_id}/termination-report`**
- Accepts termination results from agent
- Updates database with timestamps and status
- Marks instances as confirmed terminated

**GET `/api/agents/{agent_id}/replicas?status=terminated`**
- Returns replicas marked for termination
- Used by replica termination worker

**POST `/api/agents/{agent_id}/replicas/{replica_id}/status`**
- Updates replica status after termination
- Sets terminated_at timestamp

---

## DEPLOYMENT STEPS

### Step 1: Apply Database Migration on Backend Server

SSH into backend server (3.238.232.106):

```bash
# Navigate to final-ml repository
cd ~/final-ml

# Switch to the fix branch
git fetch origin claude/fix-manual-controls-visibility-0126jMKyCBaNmA1dFEPQ2ePU
git checkout claude/fix-manual-controls-visibility-0126jMKyCBaNmA1dFEPQ2ePU

# Pull latest changes
git pull origin claude/fix-manual-controls-visibility-0126jMKyCBaNmA1dFEPQ2ePU

# Apply the database migration
mysql -u root -p spot_optimizer_production < database/migrations/add_termination_tracking.sql
```

### Step 2: Verify Migration Applied

```bash
# Check instances table
mysql -u root -p spot_optimizer_production -e "SHOW COLUMNS FROM instances LIKE 'termination%';"

# Check replica_instances table
mysql -u root -p spot_optimizer_production -e "SHOW COLUMNS FROM replica_instances LIKE 'termination%';"
```

Expected output for both:
```
+---------------------------+-----------+------+-----+---------+-------+
| Field                     | Type      | Null | Key | Default | Extra |
+---------------------------+-----------+------+-----+---------+-------+
| termination_attempted_at  | timestamp | YES  | MUL | NULL    |       |
| termination_confirmed     | tinyint(1)| YES  |     | 0       |       |
+---------------------------+-----------+------+-----+---------+-------+
```

### Step 3: Restart Backend Service

```bash
# If using systemd
sudo systemctl restart spot-optimizer-backend

# Verify it's running
sudo systemctl status spot-optimizer-backend

# Check logs for any errors
sudo tail -f /var/log/spot-optimizer/backend.log
```

### Step 4: Deploy Agent Code (if not already done)

On each EC2 agent instance:

```bash
# Pull latest agent code
cd ~/agent-v2
git fetch origin claude/fix-agent-workers-017pSLG6cWuY4G2nsCSXML6p
git checkout claude/fix-agent-workers-017pSLG6cWuY4G2nsCSXML6p
git pull origin claude/fix-agent-workers-017pSLG6cWuY4G2nsCSXML6p

# Copy to agent directory
sudo cp ~/agent-v2/backend/spot_optimizer_agent.py /opt/spot-optimizer-agent/

# Restart agent
sudo systemctl restart spot-optimizer-agent

# Verify workers started
sudo tail -f /var/log/spot-optimizer/agent-error.log | grep -E "Started worker"
```

Expected output:
```
INFO - Started worker: ReplicaTermination
INFO - Started worker: Cleanup
INFO - Started worker: CommandPoller
...
```

---

## VERIFICATION

### Test Replica Termination

1. **Turn ON manual replica toggle** in UI
2. **Wait 1-2 minutes** for replica to be created and show as "ready"
3. **Turn OFF manual replica toggle** in UI
4. **Watch agent logs**:
   ```bash
   sudo tail -f /var/log/spot-optimizer/agent-error.log | grep -E "REPLICA|✓|✗"
   ```

Expected logs (within 30 seconds):
```
WARNING - 🔴 REPLICA TERMINATION: Found 1 replica(s)
WARNING - 🔧 TERMINATING REPLICA:
WARNING -    Replica ID: xxxx
WARNING -    Instance ID: i-xxxxx
INFO - ✅ Successfully terminated EC2 instance i-xxxxx
```

5. **Verify in AWS**:
   ```bash
   aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[0].Instances[0].State.Name'
   # Should return: "terminated" or "terminating"
   ```

### Test Instance Termination (Cleanup Worker)

1. **Check cleanup worker logs**:
   ```bash
   sudo tail -f /var/log/spot-optimizer/agent-error.log | grep -E "instances to terminate|✅ Successfully terminated"
   ```

Expected logs (every 60 seconds if instances exist):
```
INFO - 🔍 Checking for instances to terminate...
INFO - 🎯 Found 2 instance(s) marked for termination
INFO - 🗑️  Terminating instance: i-xxxxx (status=zombie, reason=replica promotion)
INFO - ✅ Successfully terminated i-xxxxx
INFO - ✅ Reported termination to backend
```

2. **Query backend database**:
   ```bash
   mysql -u root -p spot_optimizer_production -e "
   SELECT instance_id, instance_status, termination_attempted_at, termination_confirmed
   FROM instances
   WHERE termination_attempted_at IS NOT NULL
   ORDER BY termination_attempted_at DESC
   LIMIT 10;"
   ```

---

## TROUBLESHOOTING

### Error: "Unknown column 'termination_attempted_at'"

**Cause**: Database migration not applied

**Fix**: Run Step 1 above to apply migration

### Error: "Connection error: /api/agents/.../replicas"

**Cause**: Local API proxy not running

**Fix**:
```bash
cd ~/agent-v2/frontend
python3 api_server.py > /var/log/spot-optimizer/api.log 2>&1 &
```

### No termination logs appearing

**Cause**: Agent code not updated or worker not started

**Fix**:
```bash
# Verify worker is running
sudo grep "Started worker: ReplicaTermination" /var/log/spot-optimizer/agent-error.log

# If not found, update agent code (Step 4 above)
```

### Instances not terminating despite logs

**Cause**: Auto-terminate disabled or IAM permissions issue

**Check auto-terminate**:
```bash
sudo grep "Auto-terminate is DISABLED" /var/log/spot-optimizer/agent-error.log
```

**Check IAM permissions**:
```bash
aws ec2 terminate-instances --instance-ids i-test123 --dry-run
# Should fail with "DryRunOperation" not "UnauthorizedOperation"
```

---

## WHAT THIS FIXES

### Before:
- ❌ Replicas not terminated when toggle turned OFF
- ❌ Zombie instances left running after replica promotion
- ❌ No logging of termination attempts
- ❌ No tracking of termination status
- ❌ Backend couldn't prevent duplicate termination attempts

### After:
- ✅ Replicas terminated within 30 seconds of toggle OFF
- ✅ Zombie instances cleaned up based on terminate_wait_seconds
- ✅ Comprehensive logging with visual indicators
- ✅ Full tracking of termination attempts and confirmations
- ✅ Backend prevents duplicate attempts within 5 minutes
- ✅ Respects auto-terminate enabled/disabled setting
- ✅ Graceful error handling for all AWS API calls

---

## FILES CHANGED

### Agent Repository (agent-v2)
- `backend/spot_optimizer_agent.py` - Main agent code with termination workers
- `database/migrations/add_termination_tracking.sql` - Schema migration
- `docs/INSTANCE_TERMINATION_GUIDE.md` - Complete feature documentation
- `docs/BACKEND_SYNC_GUIDE.md` - Backend synchronization details
- `docs/REPLICA_TERMINATION_TROUBLESHOOTING.md` - Troubleshooting guide
- `scripts/diagnose-replica-termination.sh` - Diagnostic script

### Backend Repository (final-ml)
Already implemented in branch `claude/fix-manual-controls-visibility-0126jMKyCBaNmA1dFEPQ2ePU`:
- `backend/backend.py` - Endpoints for termination coordination
- `database/migrations/add_termination_tracking.sql` - Schema migration

---

## MONITORING QUERIES

### Check termination activity
```sql
-- Recent termination attempts
SELECT
    instance_id,
    instance_status,
    termination_attempted_at,
    termination_confirmed,
    TIMESTAMPDIFF(MINUTE, termination_attempted_at, NOW()) as minutes_ago
FROM instances
WHERE termination_attempted_at IS NOT NULL
ORDER BY termination_attempted_at DESC
LIMIT 20;

-- Pending terminations (attempted but not confirmed)
SELECT COUNT(*) as pending_terminations
FROM instances
WHERE termination_attempted_at IS NOT NULL
  AND termination_confirmed = FALSE
  AND TIMESTAMPDIFF(MINUTE, termination_attempted_at, NOW()) < 10;
```

### Check replica termination
```sql
SELECT
    id,
    instance_id,
    status,
    is_active,
    terminated_at,
    termination_attempted_at,
    termination_confirmed
FROM replica_instances
WHERE status = 'terminated'
ORDER BY terminated_at DESC
LIMIT 10;
```

---

## CONTACT

If issues persist after following this guide:
1. Share output of diagnostic script: `~/agent-v2/scripts/diagnose-replica-termination.sh`
2. Share last 100 lines of agent logs: `sudo tail -100 /var/log/spot-optimizer/agent-error.log`
3. Share backend response: `curl -s http://localhost:5000/api/agents/YOUR_AGENT_ID/instances-to-terminate`
