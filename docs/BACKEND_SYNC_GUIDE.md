# Backend Synchronization Guide

## Overview

This guide explains how the **Spot Optimizer Agent** (this repo) synchronizes with the **Central Backend Server** ([final-ml](https://github.com/atharva0608/final-ml)).

The agent is now **fully synchronized** with the central backend's behavior for:
1. ✅ **Replica Termination** - When manual replica toggle is turned off
2. ✅ **Auto-Terminate** - Respecting backend's `auto_terminate_enabled` setting
3. ✅ **Comprehensive Logging** - Clear visual indicators for all operations

---

## 1. Replica Termination Flow

### Backend Behavior (when manual_replica_enabled toggle is turned OFF)

From [final-ml/backend/backend.py:2598-2648](https://github.com/atharva0608/final-ml/blob/main/backend/backend.py#L2598-L2648):

```python
# Case 4: User disables manual_replica_enabled
elif 'manualReplicaEnabled' in data and not bool(data['manualReplicaEnabled']):
    updates.append("manual_replica_enabled = FALSE")

    # Terminate all active replicas for this agent
    execute_query("""
        UPDATE replica_instances
        SET is_active = FALSE, status = 'terminated', terminated_at = NOW()
        WHERE agent_id = %s
          AND is_active = TRUE
          AND status != 'promoted'
    """, (agent_id,))

    # Also mark in instances table
    execute_query("""
        UPDATE instances
        SET instance_status = 'terminated', is_active = FALSE, terminated_at = NOW()
        WHERE id = %s
    """, (replica_instance_id,))
```

**What happens:**
1. Backend updates `replica_instances` table: `status='terminated'`, `is_active=FALSE`
2. Backend also updates `instances` table with same status
3. Backend logs the termination event

### Agent Behavior (agent polls and terminates EC2 instances)

From `backend/spot_optimizer_agent.py:1780-1966`:

```python
def _replica_termination_worker(self):
    """Poll for replicas marked for termination by central backend"""

    while self.is_running:
        # Poll backend for terminated replicas
        result = self.server_api._make_request(
            'GET',
            f'/api/agents/{self.agent_id}/replicas?status=terminated'
        )

        for replica in terminated_replicas:
            replica_id = replica.get('id')
            instance_id = replica.get('instance_id')

            # Terminate actual EC2 instance
            self.instance_switcher.ec2.terminate_instances(InstanceIds=[instance_id])

            # Confirm termination to backend
            self.server_api.update_replica_status(
                self.agent_id, replica_id,
                {'status': 'terminated', 'is_active': False, 'terminated_at': ...}
            )

        # Poll every 30 seconds
        time.sleep(30)
```

**What happens:**
1. Agent polls `GET /api/agents/{id}/replicas?status=terminated` every 30s
2. Agent finds replicas marked as `status='terminated'` by backend
3. Agent calls AWS EC2 API to terminate actual instances
4. Agent confirms termination back to backend via `POST /api/agents/{id}/replicas/{replica_id}/status`

### Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ User turns OFF "Manual Replica" toggle in UI                   │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Central Backend (final-ml)                                      │
│ - Marks replica: status='terminated', is_active=FALSE           │
│ - Updates replica_instances table                               │
│ - Updates instances table                                       │
│ - Logs to system_events                                         │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ (30s polling interval)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Agent (this repo) - _replica_termination_worker                 │
│ - Polls: GET /replicas?status=terminated                        │
│ - Finds replica marked for termination                          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Agent calls AWS EC2 API                                         │
│ - ec2.terminate_instances(InstanceIds=[instance_id])            │
│ - Actually deletes the EC2 instance                             │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Agent confirms to Backend                                       │
│ - POST /replicas/{id}/status                                    │
│ - Updates: status='terminated', terminated_at=NOW()             │
└─────────────────────────────────────────────────────────────────┘
                     │
                     ▼
              ✅ COMPLETE
  EC2 instance deleted, database updated
```

---

## 2. Auto-Terminate Integration

### Backend Behavior (auto_terminate_enabled setting)

From [final-ml/backend/backend.py:1687-1713](https://github.com/atharva0608/final-ml/blob/main/backend/backend.py#L1687-L1713):

```python
# Determine terminate_wait_seconds based on auto_terminate setting
if agent['auto_terminate_enabled']:
    terminate_wait = agent['terminate_wait_seconds'] or 300
else:
    terminate_wait = 0  # Signal: DO NOT terminate old instance

# Create switch command
execute_query("""
    INSERT INTO commands (
        id, agent_id, target_mode, target_pool_id,
        terminate_wait_seconds, ...
    ) VALUES (%s, %s, %s, %s, %s, ...)
""", (command_id, agent_id, target_mode, target_pool_id, terminate_wait, ...))
```

**What happens:**
- If `auto_terminate_enabled = TRUE`: backend sets `terminate_wait_seconds = 300` (or configured value)
- If `auto_terminate_enabled = FALSE`: backend sets `terminate_wait_seconds = 0`
- Backend passes this value to agent via the `commands` table

### Agent Behavior (respects terminate_wait_seconds)

From `backend/spot_optimizer_agent.py:1171-1200`:

```python
# Get terminate_wait from command (set by backend based on auto_terminate_enabled)
terminate_wait = command.get('terminate_wait_seconds') or 0

if terminate_wait > 0:
    logger.warning(f"⏳ Auto-terminate ENABLED: waiting {terminate_wait}s...")
    time.sleep(terminate_wait)

    # Terminate old instance
    self._terminate_instance(current_instance_id)
    logger.warning(f"✅ Old instance {current_instance_id} terminated")
    logger.warning(f"   Backend will mark instance as 'terminated'")
else:
    logger.warning("🛡️  Auto-terminate DISABLED")
    logger.warning(f"   Old instance {current_instance_id} will REMAIN RUNNING")
    logger.warning(f"   Backend will mark instance as 'zombie'")
```

**What happens:**
- Agent reads `terminate_wait_seconds` from switch command
- If `> 0`: waits, then terminates old instance
- If `= 0`: keeps old instance running (backend marks it as 'zombie')

### Backend Database Updates

From [final-ml/backend/backend.py:1085-1106](https://github.com/atharva0608/final-ml/blob/main/backend/backend.py#L1085-L1106):

```python
# Handle old instance based on auto_terminate setting
if auto_terminate_enabled and timing.get('old_terminated_at'):
    # Mark old instance as terminated
    execute_query("""
        UPDATE instances
        SET is_active = FALSE,
            instance_status = 'terminated',
            is_primary = FALSE
        WHERE id = %s
    """, (old_instance_id,))
else:
    # Mark old instance as zombie (still running but not primary)
    execute_query("""
        UPDATE instances
        SET instance_status = 'zombie',
            is_primary = FALSE
        WHERE id = %s
    """, (old_instance_id,))
```

**What happens:**
- Backend receives switch report from agent
- If old instance was terminated: marks as `instance_status='terminated'`, `is_active=FALSE`
- If old instance kept running: marks as `instance_status='zombie'`, `is_primary=FALSE`

### Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ User triggers switch (UI or API)                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Backend checks agent.auto_terminate_enabled                     │
│   ┌─ TRUE  → terminate_wait_seconds = 300                       │
│   └─ FALSE → terminate_wait_seconds = 0                         │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Backend creates switch command in commands table                │
│   command.terminate_wait_seconds = (300 or 0)                   │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Agent polls and gets switch command                             │
│   reads: command.terminate_wait_seconds                         │
└────────────────────┬────────────────────────────────────────────┘
                     │
                 ┌───┴────┐
                 │        │
         (if > 0)│        │(if = 0)
                 ▼        ▼
    ┌───────────────┐  ┌────────────────────┐
    │ Wait 300s     │  │ Don't terminate    │
    │ Terminate EC2 │  │ Keep instance      │
    │ Report to     │  │ Report to backend  │
    │ backend       │  │ (no termination)   │
    └───────┬───────┘  └────────┬───────────┘
            │                   │
            ▼                   ▼
   ┌────────────────┐  ┌─────────────────┐
   │ Backend marks  │  │ Backend marks   │
   │ 'terminated'   │  │ 'zombie'        │
   └────────────────┘  └─────────────────┘
```

---

## 3. Comprehensive Logging

### Log Format

The agent now provides detailed, visually-structured logs for all operations:

```
╔══════════════════════════════════════════════════════════════╗
║  Replica Termination Worker Started                         ║
║  Polling every 30s for replicas marked 'terminated'        ║
╚══════════════════════════════════════════════════════════════╝

======================================================================
🔴 REPLICA TERMINATION: Found 2 replica(s) marked for termination by backend
======================================================================

🔧 TERMINATING REPLICA:
   Replica ID: abc-123-def-456
   Instance ID: i-0123456789abcdef0
   Type: manual
   Status: terminated
   Is Active: False

→ Checking if instance i-0123456789abcdef0 exists in AWS...
→ Instance i-0123456789abcdef0 current state: running
→ Calling AWS EC2 API: terminate_instances(i-0123456789abcdef0)...
✅ Successfully terminated EC2 instance i-0123456789abcdef0
→ Updating backend database for replica abc-123-def-456...
✅ Backend database updated successfully

✅✅✅ REPLICA abc-123-def-456 FULLY TERMINATED ✅✅✅
```

### Switch Command Logs

```
======================================================================
🔄 SWITCH COMMAND RECEIVED
   Command ID: cmd-789-xyz-123
   Target Mode: spot
   Target Pool: t3.medium.us-east-1b
   Terminate Wait: 300s
   Auto-Terminate: ENABLED
======================================================================

Starting FAST switch: i-old -> spot
...

======================================================================
🔧 AUTO-TERMINATE DECISION:
   terminate_wait_seconds: 300
   Backend auto_terminate_enabled: TRUE
======================================================================

⏳ Auto-terminate ENABLED: waiting 300s before terminating old instance...
→ Old instance i-old will be terminated after wait period
→ Wait period complete, terminating old instance i-old...
✅ Old instance i-old successfully terminated
   Backend will mark instance as 'terminated' in database
```

### Log Indicators

| Emoji | Meaning | Usage |
|-------|---------|-------|
| 🔴 | Critical Event | Replica termination triggered |
| 🔄 | Action | Switch command received |
| 🔧 | Configuration | Settings/decisions |
| ⏳ | Waiting | Time delays |
| ✅ | Success | Operation completed successfully |
| ✗ | Error | Operation failed |
| ⚠️ | Warning | Non-critical issue |
| → | Action Step | Step in a process |
| 🛡️ | Protection | Auto-terminate disabled, instance kept |
| 🛑 | Stop | Agent stopping |

---

## 4. API Endpoints Used

### Agent → Backend

| Endpoint | Method | Purpose | Polling Interval |
|----------|--------|---------|------------------|
| `/api/agents/{id}/replicas?status=terminated` | GET | Get replicas to terminate | 30s |
| `/api/agents/{id}/replicas?status=launching` | GET | Get replicas to launch | 30s |
| `/api/agents/{id}/replicas/{replica_id}/status` | POST | Update replica status | On demand |
| `/api/agents/{id}/heartbeat` | POST | Send heartbeat | 30s |
| `/api/agents/{id}/pending-commands` | GET | Get switch commands | 15s |
| `/api/agents/{id}/commands/{cmd_id}/executed` | POST | Mark command executed | On demand |
| `/api/agents/{id}/switch-report` | POST | Report switch completion | On demand |

### Expected Responses

#### GET /api/agents/{id}/replicas?status=terminated

```json
{
  "replicas": [
    {
      "id": "replica-uuid",
      "instance_id": "i-0123456789abcdef0",
      "type": "manual",
      "status": "terminated",
      "is_active": false,
      "pool": {
        "id": "t3.medium.us-east-1b",
        "az": "us-east-1b"
      }
    }
  ],
  "total": 1
}
```

#### POST /api/agents/{id}/replicas/{replica_id}/status

**Request:**
```json
{
  "status": "terminated",
  "is_active": false,
  "terminated_at": "2025-11-25T12:34:56Z"
}
```

**Response:**
```json
{
  "success": true
}
```

---

## 5. Configuration Sync

### Backend Configuration (agents table)

```sql
CREATE TABLE agents (
    id VARCHAR(36) PRIMARY KEY,
    auto_terminate_enabled BOOLEAN DEFAULT TRUE,
    terminate_wait_seconds INT DEFAULT 300,
    manual_replica_enabled BOOLEAN DEFAULT FALSE,
    auto_switch_enabled BOOLEAN DEFAULT FALSE,
    ...
);
```

### How Settings Flow to Agent

1. **User updates settings in UI** → Backend updates `agents` table
2. **Agent polls config refresh** every 60s via `GET /api/agents/{id}/config`
3. **Backend sends switch command** with `terminate_wait_seconds` based on `auto_terminate_enabled`
4. **Agent executes** switch respecting the provided `terminate_wait_seconds`

### Mutual Exclusivity

From [final-ml/backend/backend.py:2489-2491](https://github.com/atharva0608/final-ml/blob/main/backend/backend.py#L2489-L2491):

```
IMPORTANT: auto_switch_enabled and manual_replica_enabled are MUTUALLY EXCLUSIVE
- When manual_replica_enabled = ON: Manual replica maintained, no auto-switching
- When auto_switch_enabled = ON: Automatic spot optimization, no manual replicas
```

The backend enforces this:
- Enabling `auto_switch_enabled` → automatically disables `manual_replica_enabled`
- Enabling `manual_replica_enabled` → automatically disables `auto_switch_enabled`

---

## 6. Error Handling

### Agent Handles:

1. **Instance not found in AWS**
   - Logs warning
   - Updates backend database anyway
   - Continues to next replica

2. **Instance already terminated**
   - Detects via AWS API
   - Skips termination call
   - Updates backend database

3. **Network errors to backend**
   - Logs error
   - Retries on next poll (30s later)

4. **AWS API errors**
   - Logs error code and message
   - Doesn't retry immediately
   - Will retry on next poll

### Example Error Log

```
✗✗✗ AWS API ERROR during termination ✗✗✗
✗ Instance: i-0123456789abcdef0
✗ Replica: abc-123-def-456
✗ Error Code: InvalidInstanceID.NotFound
✗ Error Message: The instance ID 'i-0123456789abcdef0' does not exist
```

---

## 7. Testing the Integration

### Step 1: Verify Agent is Running with New Code

```bash
# Update agent code
sudo cp ~/agent-v2/backend/spot_optimizer_agent.py /opt/spot-optimizer-agent/

# Restart agent
sudo systemctl restart spot-optimizer-agent

# Check logs for worker start
sudo tail -f /var/log/spot-optimizer/agent-error.log | grep "ReplicaTermination"
```

Expected output:
```
INFO - Started worker: ReplicaTermination
INFO - ╔══════════════════════════════════════════════════════════════╗
INFO - ║  Replica Termination Worker Started                         ║
INFO - ║  Polling every 30s for replicas marked 'terminated'        ║
INFO - ╚══════════════════════════════════════════════════════════════╝
```

### Step 2: Test Replica Termination

```bash
# 1. Create a manual replica via UI
# 2. Turn OFF manual replica toggle
# 3. Watch logs within 30 seconds:

sudo tail -f /var/log/spot-optimizer/agent-error.log | grep -E "🔴|TERMINATING|✅"
```

Expected output:
```
WARNING - 🔴 REPLICA TERMINATION: Found 1 replica(s) marked for termination by backend
WARNING - 🔧 TERMINATING REPLICA:
INFO - → Calling AWS EC2 API: terminate_instances(i-...)...
INFO - ✅ Successfully terminated EC2 instance i-...
WARNING - ✅✅✅ REPLICA abc-123 FULLY TERMINATED ✅✅✅
```

### Step 3: Test Auto-Terminate

```bash
# 1. Enable auto_terminate in UI
# 2. Trigger a switch
# 3. Watch logs:

sudo tail -f /var/log/spot-optimizer/agent-error.log | grep -E "AUTO-TERMINATE|🔧|✅"
```

Expected with auto_terminate ENABLED:
```
WARNING - 🔧 AUTO-TERMINATE DECISION:
WARNING -    terminate_wait_seconds: 300
WARNING -    Backend auto_terminate_enabled: TRUE
WARNING - ⏳ Auto-terminate ENABLED: waiting 300s...
WARNING - ✅ Old instance i-old successfully terminated
```

Expected with auto_terminate DISABLED:
```
WARNING - 🔧 AUTO-TERMINATE DECISION:
WARNING -    terminate_wait_seconds: 0
WARNING -    Backend auto_terminate_enabled: FALSE
WARNING - 🛡️  Auto-terminate DISABLED
WARNING -    Old instance i-old will REMAIN RUNNING
WARNING -    Backend will mark instance as 'zombie'
```

---

## 8. Summary

✅ **Agent is now fully synchronized with central backend**

| Feature | Backend Behavior | Agent Behavior | Status |
|---------|-----------------|----------------|--------|
| Replica Termination | Marks `status='terminated'` | Terminates EC2 instances | ✅ Synced |
| Auto-Terminate | Sets `terminate_wait_seconds` | Respects value (0 or 300) | ✅ Synced |
| Zombie Instances | Marks as `instance_status='zombie'` | Keeps running when terminate_wait=0 | ✅ Synced |
| Logging | Standard backend logs | Comprehensive visual logs | ✅ Enhanced |

**All operations now have:**
- 🔄 Full backend synchronization
- 📝 Comprehensive logging with visual indicators
- ✅ Proper error handling
- 🔧 Configuration respect (auto_terminate_enabled, manual_replica_enabled)
