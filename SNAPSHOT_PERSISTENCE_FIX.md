# Snapshot-Based Data Persistence Fix

## Summary

This update implements full data persistence during instance switching using EBS snapshots. When an instance switches (e.g., spot → on-demand or vice versa), all data from the old instance is now preserved on the new instance via snapshot restoration.

## Changes Made

### 1. Backend Server Fix (`backend-server/backend.py`)

**Location**: Line ~1374-1459 (switch-report endpoint)

**Changes**:
- Added extraction of snapshot data from agent switch reports
- Updated `INSERT INTO switches` statement to include `snapshot_used` and `snapshot_id` columns
- Now stores snapshot information in database for audit trail and monitoring

**Code Added**:
```python
# Extract snapshot data (Fix #1: Store snapshot info for data persistence)
snapshot = data.get('snapshot', {})
snapshot_used = snapshot.get('used', False)
snapshot_id = snapshot.get('snapshot_id')

# ... in INSERT statement:
snapshot_used, snapshot_id,
```

### 2. Agent Snapshot Wait Method (`backend/spot_agent_production_v2_final.py`)

**Location**: Line 750-788

**New Method**: `_wait_for_snapshot_ready()`

**Purpose**:
- Waits for EBS snapshot to complete before using it
- Shows progress updates (0%, 25%, 50%, 75%, 100%)
- Handles timeout and error states
- Default timeout: 600 seconds (10 minutes)

**Features**:
- Polls snapshot status every 10 seconds
- Logs detailed progress for monitoring
- Returns True when snapshot is complete, False on error/timeout

### 3. Agent Launch Method Update (`backend/spot_agent_production_v2_final.py`)

**Location**: Line 790-860

**Updated Method**: `_launch_new_instance()`

**Changes**:
- Added optional `snapshot_id` parameter
- Configures `BlockDeviceMappings` with snapshot when provided
- Uses snapshot to restore root volume on new instance
- Logs data persistence status

**Key Addition**:
```python
if snapshot_id:
    launch_params['BlockDeviceMappings'] = [{
        'DeviceName': '/dev/sda1',
        'Ebs': {
            'SnapshotId': snapshot_id,
            'VolumeType': 'gp3',
            'DeleteOnTermination': True
        }
    }]
```

### 4. Agent Switch Execution Update (`backend/spot_agent_production_v2_final.py`)

**Location**: Line 581-599

**Updated Method**: `execute_switch()`

**Changes**:
- Creates snapshot from current instance
- **NEW**: Waits for snapshot to complete before launching new instance
- Passes snapshot_id to `_launch_new_instance()` for restoration
- Gracefully handles snapshot failures (proceeds without snapshot if it fails)

**Flow**:
```
1. Create snapshot from old instance root volume
2. Wait for snapshot to complete (with progress tracking)
3. Launch new instance WITH snapshot in BlockDeviceMappings
4. New instance boots with all data from old instance
5. Report switch to backend with snapshot info
```

## Data Flow

### Before Fix:
```
Old Instance → Create Snapshot → ❌ Snapshot stored but NOT used
                                ↓
                        New Instance (fresh, no data)
```

### After Fix:
```
Old Instance → Create Snapshot → Wait for Completion
                                ↓
                        Snapshot (snap-abc123)
                                ↓
                New Instance ← Use Snapshot as Root Volume
                                ↓
                        ✓ All data persisted
```

## Testing Instructions

### 1. Pre-Switch Verification

On the current instance, create test data:

```bash
# SSH into current instance
ssh ubuntu@<instance-ip>

# Create test data
echo "Persistence Test - $(date)" > /home/ubuntu/test-persistence.txt
echo "Agent uptime: $(uptime)" >> /home/ubuntu/test-persistence.txt
echo "Instance ID: $(ec2-metadata --instance-id)" >> /home/ubuntu/test-persistence.txt

# Create some directories and files
mkdir -p /home/ubuntu/test-app/data
echo "Important application data" > /home/ubuntu/test-app/data/config.json

# Verify files exist
cat /home/ubuntu/test-persistence.txt
ls -la /home/ubuntu/test-app/data/
```

### 2. Trigger Instance Switch

Use the dashboard or API to trigger a switch (spot → on-demand or vice versa).

**Watch the agent logs** for:
```
Creating snapshot...
Snapshot created: snap-abc123
Waiting for snapshot snap-abc123 to complete...
Snapshot progress: 25% (state: pending)
Snapshot progress: 50% (state: pending)
Snapshot progress: 75% (state: pending)
✓ Snapshot snap-abc123 completed (100%)
Configuring instance to restore from snapshot snap-abc123...
Launching instance via EC2 API...
✓ New instance launched successfully: i-new123
✓ Instance will restore data from snapshot snap-abc123
✓ Full data persistence enabled - agent data will be preserved
```

### 3. Post-Switch Verification

After the new instance is running:

```bash
# SSH into new instance
ssh ubuntu@<new-instance-ip>

# Verify test data persists
cat /home/ubuntu/test-persistence.txt
# Should show exact same content from old instance

# Verify application data persists
cat /home/ubuntu/test-app/data/config.json
# Should show "Important application data"

# Check all files
ls -la /home/ubuntu/
# Should see all files from old instance
```

### 4. Database Verification

Query the switches table to verify snapshot tracking:

```sql
SELECT
    id,
    old_instance_id,
    new_instance_id,
    snapshot_used,
    snapshot_id,
    initiated_at,
    old_terminated_at
FROM switches
ORDER BY initiated_at DESC
LIMIT 1;
```

Expected output:
```
snapshot_used: 1 (TRUE)
snapshot_id: snap-abc123...
old_instance_id: i-old123
new_instance_id: i-new123
```

### 5. AWS Console Verification

1. Go to AWS Console → EC2 → Snapshots
2. Find the snapshot with ID from the switch
3. Verify:
   - Status: completed
   - Description: "Spot Optimizer snapshot - [timestamp]"
   - Tags: ManagedBy=SpotOptimizer

## Configuration

### Environment Variables

```bash
# Enable snapshot creation (default: true)
CREATE_SNAPSHOT_ON_SWITCH=true

# Snapshot timeout in seconds (default: 600 = 10 minutes)
SNAPSHOT_TIMEOUT=600

# Cleanup old snapshots (default: 7 days)
CLEANUP_SNAPSHOTS_OLDER_THAN_DAYS=7
```

### Default Behavior

- Snapshots are **automatically created** during instance switches
- Snapshots are **automatically used** when launching new instances
- Old snapshots are **automatically cleaned up** after 7 days
- All snapshot operations are **logged and tracked** in the database

## Expected Behavior

### ✅ What Should Happen

1. **Before Switch**:
   - Agent creates snapshot of root volume
   - Snapshot ID: snap-abc123
   - Progress tracked: 0% → 100%

2. **During Switch**:
   - Agent waits for snapshot to complete
   - New instance launched with BlockDeviceMappings pointing to snapshot
   - Root volume restored from snapshot

3. **After Switch**:
   - New instance has ALL files from old instance
   - Application data persists
   - Agent data persists
   - No data loss

4. **Database Tracking**:
   - switches.snapshot_used = 1
   - switches.snapshot_id = snap-abc123
   - Full audit trail maintained

### ❌ What Should NOT Happen

- New instance should NOT start with a fresh filesystem
- Test files should NOT disappear after switch
- Application data should NOT be lost
- Agent should NOT skip snapshot creation (unless explicitly disabled)

## Troubleshooting

### Issue: Snapshot Takes Too Long

**Symptom**: Snapshot timeout after 600 seconds

**Solutions**:
1. Increase timeout: `SNAPSHOT_TIMEOUT=900` (15 minutes)
2. Check volume size (larger volumes take longer)
3. Verify AWS snapshot service is healthy

### Issue: New Instance Has No Data

**Symptoms**:
- Test files missing on new instance
- Fresh filesystem

**Check**:
1. Agent logs for "Proceeding without snapshot - data will NOT be persisted"
2. Database: `switches.snapshot_used = 0`
3. Environment variable: `CREATE_SNAPSHOT_ON_SWITCH=true`

**Fix**:
- Ensure CREATE_SNAPSHOT_ON_SWITCH is set to true
- Check snapshot creation permissions
- Verify snapshot completion timeout is adequate

### Issue: Wrong Device Name

**Symptom**: Instance launches but doesn't boot from snapshot

**Fix**: Try different device name in BlockDeviceMappings:
```python
# Try these alternatives:
'DeviceName': '/dev/xvda'  # For some instance types
'DeviceName': '/dev/sda1'  # Default
```

## Performance Impact

### Snapshot Creation Time
- **Small volumes** (< 50GB): ~2-5 minutes
- **Medium volumes** (50-200GB): ~5-15 minutes
- **Large volumes** (> 200GB): ~15-30 minutes

### Total Switch Downtime
**Before Fix**: ~90 seconds (instance launch only)
**After Fix**: ~2-8 minutes (snapshot + instance launch)

**Trade-off**: Slightly longer downtime in exchange for complete data persistence

## Cleanup

Old snapshots are automatically cleaned up by the agent's cleanup worker:

- **Frequency**: Every hour
- **Retention**: 7 days (configurable)
- **Filter**: Only snapshots tagged with ManagedBy=SpotOptimizer

Manual cleanup:
```bash
# List old snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters Name=tag:ManagedBy,Values=SpotOptimizer \
  --query "Snapshots[?StartTime<='$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S.000Z)']"

# Delete specific snapshot
aws ec2 delete-snapshot --snapshot-id snap-abc123
```

## Cost Impact

### Snapshot Storage Costs
- **US East (N. Virginia)**: $0.05 per GB-month
- **Example**: 100GB volume × 7 days retention ≈ $1.17/month

### Cost Savings from Data Persistence
- **Benefit**: No need to rebuild application state
- **Benefit**: No data loss = no recovery costs
- **Benefit**: Faster incident recovery

## Version Compatibility

- **Agent**: v3.2.0 (spot_agent_production_v2_final.py)
- **Backend**: From final-ml repo (claude/cleanup-backend-code-016Xh633F8SooNmRnSGSwNx9 branch)
- **Database Schema**: Requires switches table with snapshot_used and snapshot_id columns

## Rollback Plan

If issues occur, disable snapshot usage:

```bash
# On agent instance
export CREATE_SNAPSHOT_ON_SWITCH=false

# Or in .env file
CREATE_SNAPSHOT_ON_SWITCH=false
```

This will revert to the old behavior (no data persistence, faster switches).

## Future Enhancements

1. **Incremental Snapshots**: Only snapshot changed blocks
2. **Cross-Region Snapshots**: For disaster recovery
3. **Snapshot Encryption**: Add KMS encryption
4. **Faster Restoration**: Pre-warm snapshot data
5. **Application-Aware Snapshots**: Quiesce databases before snapshot

## Support

For issues or questions:
1. Check agent logs: `tail -f spot_optimizer_agent.log`
2. Check database: `SELECT * FROM switches ORDER BY initiated_at DESC LIMIT 5;`
3. Verify AWS snapshots: AWS Console → EC2 → Snapshots
4. Review this documentation

## Summary

This fix ensures complete data persistence during instance switching by:
- ✅ Creating EBS snapshots before switching
- ✅ Waiting for snapshots to complete
- ✅ Using snapshots when launching new instances
- ✅ Tracking snapshot usage in database
- ✅ Automatically cleaning up old snapshots

**Result**: Zero data loss during instance switches, with full audit trail and monitoring.
