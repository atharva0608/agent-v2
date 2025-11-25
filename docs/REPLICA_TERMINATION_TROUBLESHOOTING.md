# Replica Termination Troubleshooting Guide

## Quick Diagnosis

Run the diagnostic script on your EC2 instance:
```bash
cd ~/agent-v2/scripts
./diagnose-replica-termination.sh
```

This will test all connectivity and show you exactly what's wrong.

## Common Issues & Solutions

### Issue 1: "Connection error: /api/agents/.../replicas?status=terminated"

**Symptom:** Agent logs show connection errors when trying to fetch replicas

**Root Cause:** Local API proxy service is not running

**Solution:**
```bash
# Option 1: Start manually
cd ~/agent-v2/frontend
python3 api_server.py > /var/log/spot-optimizer/api.log 2>&1 &

# Option 2: Use systemd (if configured)
sudo systemctl start spot-optimizer-api
sudo systemctl status spot-optimizer-api

# Verify it's running
curl -s http://localhost:5000/health
```

### Issue 2: ReplicaTermination worker not found in logs

**Symptom:** No "Started worker: ReplicaTermination" message in agent logs

**Root Cause:** Agent code hasn't been updated or restarted

**Solution:**
```bash
# 1. Update agent code
sudo cp ~/agent-v2/backend/spot_optimizer_agent.py /opt/spot-optimizer-agent/

# 2. Restart agent
sudo systemctl restart spot-optimizer-agent

# 3. Verify worker started
sudo tail -f /var/log/spot-optimizer/agent-error.log | grep "ReplicaTermination"
```

### Issue 3: Replicas not being terminated

**Symptom:** Toggle is off, but EC2 instances still running

**Root Cause:** Multiple possible causes

**Diagnosis:**
```bash
# Check if worker is polling
tail -f /var/log/spot-optimizer/agent-error.log | grep -E "replica|termination"

# Check backend API response
curl -s -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:5000/api/agents/YOUR_AGENT_ID/replicas?status=terminated"
```

**Expected Logs When Working:**
```
INFO - Found 1 replica(s) marked for termination
WARNING - REPLICA TERMINATION TRIGGERED: replica_id=abc, instance_id=i-123, status=terminated, is_active=False
INFO - Calling EC2 terminate_instances for i-123
INFO - ✓ Successfully terminated EC2 instance i-123 for replica abc
INFO - ✓ Database updated for replica abc
```

## Architecture Overview

```
┌─────────────┐      ┌─────────────────┐      ┌──────────────────┐
│   Agent     │ ───> │ Local API Proxy │ ───> │ Remote Backend   │
│ (localhost) │      │ (localhost:5000)│      │ (100.28.x.x:5000)│
└─────────────┘      └─────────────────┘      └──────────────────┘
      │                                               │
      │ Polls every 30s:                             │
      │ /replicas?status=terminated                  │
      │                                               │
      └───> Terminates EC2 instances via AWS API <───┘
```

## How It Works

1. **User turns off manual replica toggle in UI**
   - Backend marks replica with `status='terminated'`
   - Backend sets `is_active=False`

2. **Agent polls every 30 seconds**
   - Calls: `GET /api/agents/{id}/replicas?status=terminated`
   - Gets list of replicas to terminate

3. **Agent terminates EC2 instances**
   - Checks if instance exists in AWS
   - Calls: `ec2.terminate_instances(InstanceIds=[instance_id])`
   - Updates database with termination timestamp

4. **Logs show the process**
   - Clear success (✓) or failure (✗) markers
   - Full details of replica_id, instance_id, status

## Backend Requirements

The backend server must implement these endpoints:

### GET /api/agents/{agent_id}/replicas?status=terminated
Returns replicas marked for termination:
```json
{
  "replicas": [
    {
      "id": "replica-uuid",
      "instance_id": "i-0123456789abcdef",
      "status": "terminated",
      "is_active": false
    }
  ]
}
```

### POST /api/agents/{agent_id}/replicas/{replica_id}/status
Updates replica status after termination:
```json
{
  "status": "terminated",
  "is_active": false,
  "terminated_at": "2025-11-25T12:00:00Z"
}
```

## Testing Replica Termination

### Step 1: Verify Services
```bash
# Check all services
spot-optimizer-status

# Should show:
# Agent Service:     ● Running
# API Service:       ● Running
# Nginx Service:     ● Running
```

### Step 2: Create Test Replica
1. Open the web UI
2. Navigate to the agent details page
3. Turn ON the "Manual Replica" toggle
4. Wait 1-2 minutes for replica to be created and show as "ready"

### Step 3: Trigger Termination
1. Turn OFF the "Manual Replica" toggle
2. Backend marks replica as `status='terminated'`

### Step 4: Watch the Logs
```bash
# Watch in real-time
tail -f /var/log/spot-optimizer/agent-error.log | grep -E "REPLICA|replica|✓|✗"

# You should see within 30 seconds:
# INFO - Found 1 replica(s) marked for termination
# WARNING - REPLICA TERMINATION TRIGGERED: ...
# INFO - ✓ Successfully terminated EC2 instance ...
```

### Step 5: Verify in AWS
```bash
# Check EC2 instance state
aws ec2 describe-instances --instance-ids i-XXXXXXXXX --query 'Reservations[0].Instances[0].State.Name'

# Should return: "terminated" or "terminating"
```

## Code Changes Summary

The fix involved two key changes to `/opt/spot-optimizer-agent/spot_optimizer_agent.py`:

### 1. Added `_replica_termination_worker` method (line 1779)
- Polls every 30 seconds for replicas with `status='terminated'`
- Checks if instance exists before terminating
- Handles already-terminated instances gracefully
- Updates database after successful termination
- Comprehensive logging with ✓/✗ markers

### 2. Updated `_start_workers` method (line 1533)
Added `(self._replica_termination_worker, "ReplicaTermination")` to workers list

## Logs to Check

### Agent Startup
```bash
grep "Started worker" /var/log/spot-optimizer/agent-error.log | tail -10
```
Should show: `Started worker: ReplicaTermination`

### Replica Termination Activity
```bash
grep -E "REPLICA TERMINATION|Successfully terminated|Failed to terminate" \
  /var/log/spot-optimizer/agent-error.log
```

### Connection Issues
```bash
grep "Connection error\|HTTP error" /var/log/spot-optimizer/agent-error.log | tail -20
```

## Still Having Issues?

1. **Run the diagnostic script:**
   ```bash
   ~/agent-v2/scripts/diagnose-replica-termination.sh
   ```

2. **Check all logs:**
   ```bash
   spot-optimizer-logs
   ```

3. **Verify agent code is updated:**
   ```bash
   grep "_replica_termination_worker" /opt/spot-optimizer-agent/spot_optimizer_agent.py
   ```

4. **Test API connectivity manually:**
   ```bash
   # Test local proxy
   curl -s http://localhost:5000/health

   # Test with auth
   curl -s -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:5000/api/agents/YOUR_AGENT_ID/replicas?status=terminated
   ```

## Contact

If you've tried everything above and replicas still aren't terminating:
1. Share the output of `diagnose-replica-termination.sh`
2. Share the last 100 lines of agent logs
3. Share the response from the API endpoint (replicas?status=terminated)
