# Data Persistence Analysis & Fix

## Current Status Summary

### ✅ What's Working
1. **Snapshot Creation**: Agent creates EBS snapshots before switching (spot_agent_production_v2_final.py:582-584)
2. **Snapshot Data Sent**: Agent sends snapshot info to backend in switch report (line 675)
3. **Database Schema**: Backend database has `snapshot_used` and `snapshot_id` columns in switches table

### ❌ Critical Issues Found

#### Issue #1: Backend Not Storing Snapshot Data
**Location**: `final-ml/backend/backend.py` line ~1416 (INSERT INTO switches)

**Problem**: The backend receives snapshot data from the agent but does NOT store it in the database.

**Current Code** (missing snapshot fields):
```python
execute_query("""
    INSERT INTO switches (
        id, client_id, agent_id, command_id,
        old_instance_id, old_instance_type, old_region, old_az, old_mode, old_pool_id, old_ami_id,
        new_instance_id, new_instance_type, new_region, new_az, new_mode, new_pool_id, new_ami_id,
        on_demand_price, old_spot_price, new_spot_price, savings_impact,
        event_trigger, trigger_type, timing_data,
        initiated_at, ami_created_at, instance_launched_at, instance_ready_at, old_terminated_at,
        downtime_seconds, total_duration_seconds
    ) VALUES (...)
```

**Missing**: `snapshot_used`, `snapshot_id` columns

#### Issue #2: Agent Not Using Snapshot for New Instance
**Location**: `agent-v2/backend/spot_agent_production_v2_final.py` line ~750-803

**Problem**: The agent creates a snapshot but does NOT use it when launching the new instance. This means:
- Agent data is NOT persisted
- Full data is NOT transferred to new instance
- New instance starts fresh without previous state

**Current Code** (line 787-789):
```python
launch_params = {
    'ImageId': current_instance['ami_id'],  # Uses SAME AMI
    'InstanceType': current_instance['instance_type'],
    'MinCount': 1,
    'MaxCount': 1,
    ...
}
```

**Missing**: BlockDeviceMappings with snapshot_id to restore the volume

#### Issue #3: No Snapshot Restoration Logic
The agent needs to:
1. Create snapshot from current instance's root volume ✅ (Already done)
2. Wait for snapshot to complete (MISSING)
3. Use snapshot in BlockDeviceMappings when launching new instance (MISSING)
4. Verify data integrity after launch (MISSING)

## Required Fixes

### Fix #1: Update Backend to Store Snapshot Data

**File**: `final-ml/backend/backend.py`
**Location**: ~line 1416 (switch-report endpoint)

Add snapshot fields to INSERT statement:

```python
# Extract snapshot data
snapshot = data.get('snapshot', {})
snapshot_used = snapshot.get('used', False)
snapshot_id = snapshot.get('snapshot_id')

# Update INSERT statement
execute_query("""
    INSERT INTO switches (
        id, client_id, agent_id, command_id,
        old_instance_id, old_instance_type, old_region, old_az, old_mode, old_pool_id, old_ami_id,
        new_instance_id, new_instance_type, new_region, new_az, new_mode, new_pool_id, new_ami_id,
        on_demand_price, old_spot_price, new_spot_price, savings_impact,
        event_trigger, trigger_type, timing_data,
        snapshot_used, snapshot_id,  # ADD THIS
        initiated_at, ami_created_at, instance_launched_at, instance_ready_at, old_terminated_at,
        downtime_seconds, total_duration_seconds
    ) VALUES (
        %s, %s, %s, %s,
        %s, %s, %s, %s, %s, %s, %s,
        %s, %s, %s, %s, %s, %s, %s,
        %s, %s, %s, %s,
        %s, %s, %s,
        %s, %s,  # ADD THIS
        %s, %s, %s, %s, %s,
        %s, %s
    )
""", (
    switch_id, request.client_id, agent_id, data.get('command_id'),
    old_inst.get('instance_id'), old_inst.get('instance_type'), old_inst.get('region'),
    old_inst.get('az'), old_inst.get('mode'), old_inst.get('pool_id'), old_inst.get('ami_id'),
    new_inst.get('instance_id'), new_inst.get('instance_type'), new_inst.get('region'),
    new_inst.get('az'), new_inst.get('mode'), new_inst.get('pool_id'), new_inst.get('ami_id'),
    prices.get('on_demand'), prices.get('old_spot'), prices.get('new_spot'), savings_impact,
    data.get('trigger'), data.get('trigger'), json.dumps(timing),
    snapshot_used, snapshot_id,  # ADD THIS
    timing.get('initiated_at'), timing.get('ami_created_at'),
    timing.get('instance_launched_at'), timing.get('instance_ready_at'),
    timing.get('old_terminated_at'),
    downtime_seconds, total_duration_seconds
))
```

### Fix #2: Update Agent to Use Snapshot When Launching New Instance

**File**: `agent-v2/backend/spot_agent_production_v2_final.py`
**Location**: Lines 750-803 (_launch_new_instance method)

Add snapshot restoration logic:

```python
def _launch_new_instance(self, current_instance: Dict, target_mode: str,
                        target_pool_id: Optional[str], snapshot_id: Optional[str] = None) -> Optional[str]:
    """Launch new instance with optional snapshot restoration"""
    try:
        logger.info(f"Preparing to launch {target_mode} instance...")
        logger.info(f"  AMI: {current_instance['ami_id']}")
        logger.info(f"  Instance Type: {current_instance['instance_type']}")

        if snapshot_id:
            logger.info(f"  Snapshot: {snapshot_id} (for data persistence)")

        launch_params = {
            'ImageId': current_instance['ami_id'],
            'InstanceType': current_instance['instance_type'],
            'MinCount': 1,
            'MaxCount': 1,
            'TagSpecifications': [{
                'ResourceType': 'instance',
                'Tags': [
                    {'Key': 'Name', 'Value': f"SpotOptimizer-{target_mode}"},
                    {'Key': 'ManagedBy', 'Value': 'SpotOptimizer'},
                    {'Key': 'LogicalAgentId', 'Value': config.LOGICAL_AGENT_ID}
                ]
            }]
        }

        # ADD SNAPSHOT RESTORATION
        if snapshot_id:
            logger.info(f"Configuring instance to restore from snapshot {snapshot_id}...")
            launch_params['BlockDeviceMappings'] = [{
                'DeviceName': '/dev/sda1',  # Root volume device
                'Ebs': {
                    'SnapshotId': snapshot_id,
                    'VolumeType': 'gp3',
                    'DeleteOnTermination': True
                }
            }]

        if target_mode == 'spot' and target_pool_id:
            # Extract AZ from pool_id
            az = target_pool_id.split('.')[-1]
            logger.info(f"  Target AZ: {az} (from pool {target_pool_id})")
            launch_params['Placement'] = {'AvailabilityZone': az}
            launch_params['InstanceMarketOptions'] = {
                'MarketType': 'spot',
                'SpotOptions': {
                    'SpotInstanceType': 'one-time',
                    'InstanceInterruptionBehavior': 'terminate'
                }
            }
        elif target_mode == 'ondemand':
            logger.info(f"  Target mode: On-Demand")

        logger.info("Launching instance via EC2 API...")
        response = self.ec2.run_instances(**launch_params)

        new_instance_id = response['Instances'][0]['InstanceId']
        logger.info(f"✓ New instance launched successfully: {new_instance_id}")

        if snapshot_id:
            logger.info(f"✓ Instance will restore data from snapshot {snapshot_id}")

        return new_instance_id
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_msg = e.response.get('Error', {}).get('Message', str(e))
        logger.error(f"AWS API error launching instance: {error_code} - {error_msg}")
        return None
    except Exception as e:
        logger.error(f"Failed to launch instance: {e}", exc_info=True)
        return None
```

### Fix #3: Update execute_switch to Wait for Snapshot and Use It

**File**: `agent-v2/backend/spot_agent_production_v2_final.py`
**Location**: Lines 554-688 (execute_switch method)

```python
# Step 1: Create snapshot if enabled
snapshot_data = {'used': False}
snapshot_id = None
if config.CREATE_SNAPSHOT_ON_SWITCH:
    snapshot_data = self._create_snapshot(current_instance)
    if snapshot_data['used']:
        snapshot_id = snapshot_data['snapshot_id']
        logger.info(f"Waiting for snapshot {snapshot_id} to complete...")
        # Wait for snapshot to be ready
        if not self._wait_for_snapshot_ready(snapshot_id):
            logger.error("Snapshot failed to complete in time")
            snapshot_id = None
            snapshot_data['used'] = False

# Step 2: Launch new instance WITH SNAPSHOT
new_instance_id = self._launch_new_instance(
    current_instance, target_mode, target_pool_id, snapshot_id  # ADD snapshot_id parameter
)
```

### Fix #4: Add Snapshot Wait Method

**File**: `agent-v2/backend/spot_agent_production_v2_final.py`
**Add new method**:

```python
def _wait_for_snapshot_ready(self, snapshot_id: str, timeout: int = 600) -> bool:
    """Wait for snapshot to complete"""
    try:
        logger.info(f"Waiting for snapshot {snapshot_id} to complete...")
        start_time = time.time()

        while time.time() - start_time < timeout:
            response = self.ec2.describe_snapshots(SnapshotIds=[snapshot_id])
            if not response['Snapshots']:
                logger.error(f"Snapshot {snapshot_id} not found")
                return False

            state = response['Snapshots'][0]['State']
            progress = response['Snapshots'][0].get('Progress', '0%')

            if state == 'completed':
                logger.info(f"✓ Snapshot {snapshot_id} completed")
                return True
            elif state == 'error':
                logger.error(f"Snapshot {snapshot_id} failed")
                return False

            logger.info(f"Snapshot progress: {progress} (state: {state})")
            time.sleep(10)

        logger.error(f"Snapshot {snapshot_id} timeout after {timeout}s")
        return False
    except Exception as e:
        logger.error(f"Failed to wait for snapshot: {e}")
        return False
```

## Sync Strategy

### 1. Copy Central Backend to agent-v2 Repo

```bash
# Create backend-server directory in agent-v2
mkdir -p /home/user/agent-v2/backend-server

# Copy backend files from final-ml
cp /tmp/final-ml/backend/backend.py /home/user/agent-v2/backend-server/
cp /tmp/final-ml/backend/repositories.py /home/user/agent-v2/backend-server/
cp /tmp/final-ml/backend/exceptions.py /home/user/agent-v2/backend-server/
cp /tmp/final-ml/backend/smart_emergency_fallback.py /home/user/agent-v2/backend-server/
cp /tmp/final-ml/backend/requirements.txt /home/user/agent-v2/backend-server/
cp -r /tmp/final-ml/backend/decision_engines /home/user/agent-v2/backend-server/

# Copy database schema
cp -r /tmp/final-ml/database /home/user/agent-v2/backend-server/

# Copy environment example
cp /tmp/final-ml/backend/.env.example /home/user/agent-v2/backend-server/
```

### 2. Apply All Fixes

1. Update backend.py to store snapshot data
2. Update spot_agent_production_v2_final.py to use snapshots
3. Test the integration

## Testing Checklist

- [ ] Snapshot is created before instance switch
- [ ] Snapshot ID is stored in database
- [ ] New instance uses snapshot for root volume
- [ ] Agent data persists across switch
- [ ] Full data is available on new instance
- [ ] Old snapshots are cleaned up properly

## Configuration

Add to `.env` on agent instances:

```bash
# Snapshot configuration
CREATE_SNAPSHOT_ON_SWITCH=true
SNAPSHOT_TIMEOUT=600  # 10 minutes

# Cleanup configuration
CLEANUP_SNAPSHOTS_OLDER_THAN_DAYS=7
```

## Expected Behavior After Fix

1. Agent creates snapshot of current instance root volume
2. Agent waits for snapshot to complete (shows progress: 0%, 25%, 50%, 75%, 100%)
3. Agent launches new instance with BlockDeviceMappings pointing to snapshot
4. New instance boots with all data from previous instance
5. Backend stores snapshot_id in switches table for audit trail
6. Old snapshots are cleaned up after 7 days

## Data Persistence Verification

After implementing fixes, verify:

1. **Create test file on instance**:
   ```bash
   echo "test-data-$(date)" > /home/ubuntu/persistence-test.txt
   ```

2. **Trigger instance switch** (spot -> on-demand or vice versa)

3. **Check new instance**:
   ```bash
   cat /home/ubuntu/persistence-test.txt
   # Should show the same content
   ```

4. **Verify database**:
   ```sql
   SELECT snapshot_used, snapshot_id, old_instance_id, new_instance_id
   FROM switches
   ORDER BY initiated_at DESC
   LIMIT 1;
   ```

Should show:
- `snapshot_used`: 1 (true)
- `snapshot_id`: snap-xxxxxxxx
- Both instance IDs populated
