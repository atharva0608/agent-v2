# Instance Termination Implementation - Complete Guide

## Overview

The agent now fully implements instance termination for:
1. **Zombie Instances** - Old primary instances after replica promotion
2. **Terminated Replicas** - Replica instances when manual replica mode is disabled

This document explains how the agent's cleanup worker terminates instances marked for termination by the central backend.

---

## How It Works

### Complete Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Backend Event (e.g., Manual Replica Toggle OFF)             │
│    - Backend marks replica: status='terminated'                 │
│    - Backend marks instance: instance_status='terminated'       │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Agent Cleanup Worker Polls (every 60 seconds)               │
│    GET /api/agents/{id}/instances-to-terminate                  │
│    - Returns zombie instances past wait period                  │
│    - Returns terminated replicas                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Agent Checks Auto-Terminate Setting                         │
│    if auto_terminate_enabled = FALSE:                           │
│        → Skip termination, keep instances running               │
│    if auto_terminate_enabled = TRUE:                            │
│        → Continue to termination                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Agent Terminates via AWS EC2 API                            │
│    - ec2.describe_instances() - Check if exists                 │
│    - ec2.terminate_instances() - Terminate                      │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Agent Reports Back to Backend                               │
│    POST /api/agents/{id}/termination-report                     │
│    - success: true/false                                        │
│    - error: error message (if failed)                           │
│    - terminated_at: timestamp                                   │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Backend Updates Database                                    │
│    - Sets termination_confirmed = TRUE                          │
│    - Sets terminated_at = NOW()                                 │
│    - Logs to system_events table                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Details

### 1. Cleanup Worker Architecture

The cleanup worker now runs two types of operations:

| Operation | Interval | Description |
|-----------|----------|-------------|
| **AMI/Snapshot Cleanup** | 1 hour | Cleans up old AMIs and snapshots |
| **Instance Termination** | 60 seconds | Terminates zombie/terminated instances |

**Why 60 seconds?**
- Fast response to replica toggle OFF
- Catches zombie instances soon after wait period expires
- Low overhead on backend/AWS APIs

### 2. Backend Endpoints Used

#### GET /api/agents/{agent_id}/instances-to-terminate

**Response:**
```json
{
  "instances": [
    {
      "instance_id": "i-0123456789abcdef0",
      "instance_type": "c5.large",
      "az": "us-east-1a",
      "reason": "zombie_timeout",
      "seconds_waiting": 320
    },
    {
      "instance_id": "i-0987654321fedcba0",
      "instance_type": "c5.large",
      "az": "us-east-1b",
      "reason": "replica_terminated",
      "seconds_since_marked": 5
    }
  ],
  "auto_terminate_enabled": true,
  "terminate_wait_seconds": 300
}
```

**Backend Logic:**
- Only returns instances if `auto_terminate_enabled = TRUE`
- Returns zombie instances with `TIMESTAMPDIFF(SECOND, updated_at, NOW()) >= terminate_wait_seconds`
- Returns replica instances with `status = 'terminated'` and `termination_attempted_at IS NULL`
- Prevents duplicate attempts: won't return if `termination_attempted_at < NOW() - 5 minutes`

#### POST /api/agents/{agent_id}/termination-report

**Request:**
```json
{
  "instance_id": "i-0123456789abcdef0",
  "success": true,
  "error": null,
  "terminated_at": "2025-11-25T12:30:00Z"
}
```

**Backend Actions on Success:**
```sql
UPDATE instances
SET instance_status = 'terminated',
    is_active = FALSE,
    terminated_at = %s,
    termination_attempted_at = NOW(),
    termination_confirmed = TRUE
WHERE id = %s;

UPDATE replica_instances
SET status = 'terminated',
    terminated_at = %s,
    termination_attempted_at = NOW(),
    termination_confirmed = TRUE
WHERE instance_id = %s;

INSERT INTO system_events (event_type, severity, agent_id, message, metadata)
VALUES ('instance_terminated', 'info', %s, %s, %s);
```

**Backend Actions on Failure:**
```sql
UPDATE instances
SET termination_attempted_at = NOW()
WHERE id = %s;

INSERT INTO system_events (event_type, severity, agent_id, message, metadata)
VALUES ('instance_termination_failed', 'warning', %s, %s, %s);
```

### 3. Agent Methods

#### `_terminate_marked_instances()`

**Purpose:** Main orchestrator for instance termination

**Steps:**
1. Poll backend for instances to terminate
2. Check if `auto_terminate_enabled = TRUE`
3. Loop through each instance
4. Call `_terminate_instance_via_aws()`
5. Report success/failure to backend

**Error Handling:**
- Catches all exceptions per instance
- Reports failures to backend
- Continues with next instance even if one fails

#### `_terminate_instance_via_aws(instance_id)`

**Purpose:** Terminate a single instance via AWS EC2 API

**Steps:**
1. Check if instance exists: `describe_instances()`
2. Check current state (terminated/terminating/running)
3. Terminate: `terminate_instances()`
4. Verify termination initiated

**Error Handling:**
- `InvalidInstanceID.NotFound` → Treat as success (already gone)
- `UnauthorizedOperation` → Raise exception (need IAM permissions)
- Other AWS errors → Raise for caller to report to backend

---

## When Instances Are Marked for Termination

### Scenario 1: Manual Replica Disabled

**User Action:** Turn OFF "Manual Replica" toggle in UI

**Backend (final-ml/backend/backend.py:2598-2648):**
```python
# When user disables manual_replica_enabled
updates.append("manual_replica_enabled = FALSE")

# Terminate all active replicas for this agent
execute_query("""
    UPDATE replica_instances
    SET is_active = FALSE, status = 'terminated', terminated_at = NOW()
    WHERE agent_id = %s AND is_active = TRUE AND status != 'promoted'
""", (agent_id,))

# Also mark in instances table
execute_query("""
    UPDATE instances
    SET instance_status = 'terminated', is_active = FALSE, terminated_at = NOW()
    WHERE id = %s
""", (replica_instance_id,))
```

**Agent:**
- Polls every 60 seconds
- Finds replica with `reason = 'replica_terminated'`
- Terminates EC2 instance immediately (no wait period)
- Reports success to backend

### Scenario 2: Replica Promotion (Zombie Timeout)

**User Action:** Promote replica to primary via UI

**Backend:**
1. Promotes replica to primary
2. Marks old primary as 'zombie': `instance_status = 'zombie', is_primary = FALSE`
3. Does NOT terminate immediately

**Agent (After terminate_wait_seconds expires):**
1. Polls every 60 seconds
2. After 300 seconds (default), finds zombie with `reason = 'zombie_timeout'`
3. Terminates EC2 instance
4. Reports success to backend

**Why the wait?**
- Allows time for graceful shutdown
- Ensures new primary is stable before terminating old one
- Configurable via `terminate_wait_seconds` (default: 300)

### Scenario 3: Auto-Terminate Disabled

**User Action:** Disable `auto_terminate_enabled` in agent settings

**Backend:**
- Still marks instances as 'zombie' or 'terminated' in database
- Returns empty array from `/instances-to-terminate` endpoint
- `auto_terminate_enabled = FALSE` in response

**Agent:**
- Polls every 60 seconds
- Sees `auto_terminate_enabled = FALSE`
- Logs: "🛡️  Auto-terminate is DISABLED - skipping instance termination"
- Does NOT terminate any instances
- Instances remain running in AWS

---

## Logging

### Cleanup Worker Start

```
╔══════════════════════════════════════════════════════════════╗
║  Cleanup Worker Started                                     ║
║  - AMI/Snapshot cleanup every 1 hour                        ║
║  - Instance termination check every 60 seconds              ║
╚══════════════════════════════════════════════════════════════╝
```

### AMI/Snapshot Cleanup (Every 1 Hour)

```
══════════════════════════════════════════════════════════════════
🧹 Running AMI/Snapshot cleanup operations...
══════════════════════════════════════════════════════════════════
✅ Cleanup completed: 5 snapshots, 2 AMIs deleted
```

### Instance Termination (Every 60 Seconds)

**When instances found:**
```
======================================================================
🗑️  INSTANCE TERMINATION: Found 2 instance(s) to terminate
   Auto-terminate: ENABLED
   Terminate wait: 300s
======================================================================

🔧 TERMINATING INSTANCE:
   Instance ID: i-0123456789abcdef0
   Instance Type: c5.large
   AZ: us-east-1a
   Reason: zombie_timeout
   Wait Time: 320s

→ Checking if instance i-0123456789abcdef0 exists in AWS...
→ Instance i-0123456789abcdef0 current state: running
→ Calling AWS EC2 API: terminate_instances(i-0123456789abcdef0)...
✓ Instance i-0123456789abcdef0 state: running → shutting-down
✅ Successfully terminated EC2 instance i-0123456789abcdef0

✅✅✅ INSTANCE i-0123456789abcdef0 TERMINATED SUCCESSFULLY ✅✅✅
```

**When auto-terminate disabled:**
```
Checking for instances to terminate...
🛡️  Auto-terminate is DISABLED - skipping instance termination
```

**When no instances to terminate:**
```
Checking for instances to terminate...
No instances to terminate
```

### Error Scenarios

**Instance Not Found:**
```
→ Checking if instance i-0123456789abcdef0 exists in AWS...
⚠️  Instance i-0123456789abcdef0 not found in AWS (InvalidInstanceID)
→ Instance already terminated - reporting success
✅✅✅ INSTANCE i-0123456789abcdef0 TERMINATED SUCCESSFULLY ✅✅✅
```

**AWS API Error:**
```
✗✗✗ AWS API ERROR during instance termination ✗✗✗
✗ Instance: i-0123456789abcdef0
✗ Error Code: UnauthorizedOperation
✗ Error Message: You are not authorized to perform this operation
```

**Unexpected Error:**
```
✗✗✗ UNEXPECTED ERROR during instance termination ✗✗✗
✗ Instance: i-0123456789abcdef0
✗ Error: Connection timeout
```

---

## Safety Features

### 1. Auto-Terminate Check

**Protection:** Only terminates if explicitly enabled

```python
if not auto_terminate_enabled:
    logger.debug("🛡️  Auto-terminate is DISABLED - skipping instance termination")
    return
```

**How to Control:**
- UI: Agent settings → "Auto-Terminate Enabled" toggle
- Backend: `agents.auto_terminate_enabled` column
- Default: `TRUE` (enabled)

### 2. Wait Period for Zombies

**Protection:** Zombies wait before termination

```python
# Backend only returns zombies past the wait period
TIMESTAMPDIFF(SECOND, i.updated_at, NOW()) >= terminate_wait_seconds
```

**How to Control:**
- UI: Agent settings → "Terminate Wait Seconds"
- Backend: `agents.terminate_wait_seconds` column
- Default: `300` seconds (5 minutes)

### 3. Duplicate Prevention

**Protection:** Prevents duplicate termination attempts

```python
# Backend filter
AND (termination_attempted_at IS NULL
     OR termination_attempted_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE))
```

**How it works:**
- Backend tracks `termination_attempted_at` timestamp
- Won't return same instance again within 5 minutes
- Allows retry after 5 minutes if first attempt failed

### 4. Instance Existence Checks

**Protection:** Checks before terminating

```python
# Agent checks if instance exists
describe_response = self.instance_switcher.ec2.describe_instances(InstanceIds=[instance_id])

# Checks current state
if instance_state in ['terminated', 'terminating']:
    return  # Already terminated
```

**Benefits:**
- Avoids errors for already-terminated instances
- Gracefully handles AWS inconsistencies
- Reports success even if instance already gone

### 5. Error Reporting

**Protection:** All failures reported to backend

```python
# On failure
self.server_api.report_instance_termination(
    self.agent_id, instance_id,
    success=False,
    error=f"{error_code}: {error_msg}"
)
```

**Benefits:**
- Backend knows about failures
- System events logged for monitoring
- Allows investigation and manual intervention

---

## Testing

### Test 1: Manual Replica Disabled

**Steps:**
1. Enable manual replica mode for an agent
2. Wait for replica to be created (status='ready')
3. Disable manual replica mode
4. Wait up to 60 seconds
5. Check agent logs

**Expected Logs:**
```
🗑️  INSTANCE TERMINATION: Found 1 instance(s) to terminate
🔧 TERMINATING INSTANCE:
   Instance ID: i-xxx
   Reason: replica_terminated
✅✅✅ INSTANCE i-xxx TERMINATED SUCCESSFULLY ✅✅✅
```

**Verification:**
```bash
# Check AWS
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].State.Name'
# Should return: "terminated" or "shutting-down"

# Check database
mysql> SELECT instance_id, status, termination_confirmed, terminated_at
       FROM replica_instances
       WHERE instance_id = 'i-xxx';
# Should show: termination_confirmed=1, terminated_at=<timestamp>
```

### Test 2: Replica Promotion (Zombie Timeout)

**Steps:**
1. Enable manual replica mode
2. Promote replica to primary
3. Old primary becomes 'zombie'
4. Wait for `terminate_wait_seconds` + 60 seconds
5. Check agent logs

**Expected Logs:**
```
🗑️  INSTANCE TERMINATION: Found 1 instance(s) to terminate
🔧 TERMINATING INSTANCE:
   Instance ID: i-old-primary
   Reason: zombie_timeout
   Wait Time: 305s
✅✅✅ INSTANCE i-old-primary TERMINATED SUCCESSFULLY ✅✅✅
```

**Verification:**
```bash
# Check database
mysql> SELECT id, instance_status, termination_confirmed, terminated_at
       FROM instances
       WHERE id = 'i-old-primary';
# Should show: instance_status='terminated', termination_confirmed=1
```

### Test 3: Auto-Terminate Disabled

**Steps:**
1. Disable `auto_terminate_enabled` for agent
2. Perform any action that marks instance as zombie/terminated
3. Wait 60 seconds
4. Check agent logs

**Expected Logs:**
```
Checking for instances to terminate...
🛡️  Auto-terminate is DISABLED - skipping instance termination
```

**Verification:**
```bash
# Check AWS - instance should still be running
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].State.Name'
# Should return: "running"
```

### Test 4: Instance Already Terminated

**Steps:**
1. Manually terminate instance via AWS console
2. Backend still has it marked as needs termination
3. Wait for agent to poll
4. Check agent logs

**Expected Logs:**
```
→ Checking if instance i-xxx exists in AWS...
⚠️  Instance i-xxx not found in AWS (InvalidInstanceID)
→ Instance already terminated - reporting success
✅✅✅ INSTANCE i-xxx TERMINATED SUCCESSFULLY ✅✅✅
```

---

## IAM Permissions Required

The agent's IAM role **MUST** have these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowInstanceTermination",
      "Effect": "Allow",
      "Action": [
        "ec2:TerminateInstances",
        "ec2:DescribeInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:Region": "us-east-1"
        }
      }
    }
  ]
}
```

**Important:**
- Adjust `ec2:Region` to match your deployment region
- `ec2:DescribeInstances` - Check if instance exists before terminating
- `ec2:TerminateInstances` - Actually terminate the instance
- `Resource: "*"` - Required because instance IDs are dynamic

**Error if Missing:**
```
✗✗✗ AWS API ERROR during instance termination ✗✗✗
✗ Error Code: UnauthorizedOperation
✗ Error Message: You are not authorized to perform this operation
```

---

## Troubleshooting

### Issue 1: Instances Not Being Terminated

**Symptom:** Database shows instances as 'zombie' or 'terminated', but AWS shows them running

**Possible Causes:**

1. **Auto-terminate disabled**
   ```bash
   # Check database
   mysql> SELECT auto_terminate_enabled FROM agents WHERE id = 'agent-id';
   ```
   **Fix:** Enable in UI: Agent Settings → Auto-Terminate Enabled

2. **IAM permissions missing**
   ```bash
   # Check agent logs
   tail -f /var/log/spot-optimizer/agent-error.log | grep UnauthorizedOperation
   ```
   **Fix:** Add EC2 termination permissions to agent's IAM role

3. **Cleanup worker not running**
   ```bash
   # Check if worker started
   tail -f /var/log/spot-optimizer/agent-error.log | grep "Cleanup Worker Started"
   ```
   **Fix:** Restart agent

4. **Zombie wait period not expired**
   ```bash
   # Check how long zombie has been waiting
   mysql> SELECT id, TIMESTAMPDIFF(SECOND, updated_at, NOW()) as seconds_waiting
          FROM instances
          WHERE instance_status = 'zombie';
   ```
   **Fix:** Wait for `terminate_wait_seconds` to expire (default 300s)

5. **Network connectivity issues**
   ```bash
   # Check agent logs for connection errors
   tail -f /var/log/spot-optimizer/agent-error.log | grep "Connection error"
   ```
   **Fix:** Check security groups, network connectivity to backend

### Issue 2: Cleanup Worker Not Starting

**Symptom:** No "Cleanup Worker Started" log message

**Diagnosis:**
```bash
# Check if agent is running
systemctl status spot-optimizer-agent

# Check for errors during startup
tail -100 /var/log/spot-optimizer/agent-error.log | grep -A 5 "ERROR"
```

**Common Causes:**
- Agent startup failed due to missing dependencies
- Config file errors
- Permission issues

### Issue 3: High Termination Failure Rate

**Symptom:** Many instances failing to terminate

**Diagnosis:**
```bash
# Check system events
mysql> SELECT * FROM system_events
       WHERE event_type = 'instance_termination_failed'
       ORDER BY created_at DESC
       LIMIT 20;

# Check agent logs for patterns
tail -100 /var/log/spot-optimizer/agent-error.log | grep "✗✗✗"
```

**Common Causes:**
- IAM permissions insufficient
- AWS API throttling (rate limits)
- Instance IDs invalid (already terminated by someone else)

---

## Monitoring

### Metrics to Track

1. **Termination Success Rate**
   ```sql
   SELECT
       DATE(created_at) as date,
       SUM(CASE WHEN event_type = 'instance_terminated' THEN 1 ELSE 0 END) as successes,
       SUM(CASE WHEN event_type = 'instance_termination_failed' THEN 1 ELSE 0 END) as failures,
       ROUND(SUM(CASE WHEN event_type = 'instance_terminated' THEN 1 ELSE 0 END) * 100.0 /
             (SUM(CASE WHEN event_type = 'instance_terminated' THEN 1 ELSE 0 END) +
              SUM(CASE WHEN event_type = 'instance_termination_failed' THEN 1 ELSE 0 END)), 2) as success_rate
   FROM system_events
   WHERE event_type IN ('instance_terminated', 'instance_termination_failed')
   GROUP BY DATE(created_at)
   ORDER BY date DESC
   LIMIT 30;
   ```

2. **Average Time from Marking to Termination**
   ```sql
   SELECT AVG(TIMESTAMPDIFF(SECOND, terminated_at, termination_attempted_at)) as avg_seconds
   FROM instances
   WHERE termination_confirmed = TRUE
     AND terminated_at IS NOT NULL
     AND termination_attempted_at IS NOT NULL;
   ```

3. **Instances Pending Termination**
   ```sql
   SELECT COUNT(*) as pending_count
   FROM instances
   WHERE instance_status IN ('zombie', 'terminated')
     AND (termination_confirmed = FALSE OR termination_confirmed IS NULL);
   ```

### Dashboard Queries

**Current Status:**
```sql
SELECT
    instance_status,
    COUNT(*) as count,
    SUM(CASE WHEN termination_confirmed = TRUE THEN 1 ELSE 0 END) as confirmed_terminated
FROM instances
GROUP BY instance_status;
```

**Recent Terminations:**
```sql
SELECT
    instance_id,
    instance_type,
    instance_status,
    terminated_at,
    termination_attempted_at,
    TIMESTAMPDIFF(SECOND, terminated_at, termination_attempted_at) as termination_latency_seconds
FROM instances
WHERE termination_confirmed = TRUE
ORDER BY terminated_at DESC
LIMIT 20;
```

---

## Summary

✅ **Agent now fully terminates instances marked by backend**

| Feature | Status |
|---------|--------|
| Cleanup worker polls every 60 seconds | ✅ Implemented |
| Terminates zombie instances | ✅ Implemented |
| Terminates replica instances | ✅ Implemented |
| Respects auto_terminate_enabled | ✅ Implemented |
| Respects terminate_wait_seconds | ✅ Implemented |
| Reports results to backend | ✅ Implemented |
| Comprehensive logging | ✅ Implemented |
| Error handling | ✅ Implemented |
| Safety checks | ✅ Implemented |

**Full synchronization with final-ml backend achieved!** 🎉
