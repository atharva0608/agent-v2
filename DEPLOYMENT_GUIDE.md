# AWS Spot Optimizer - Deployment & Testing Guide
**Date**: 2025-11-26
**Version**: Agent v4.0.0 + Backend v5.1

## Quick Start

This guide will help you:
1. Apply the required database migration to your central backend
2. Verify AWS permissions are configured correctly
3. Test the complete termination workflow
4. Monitor the system in production

## Prerequisites

Before starting, ensure you have:
- [ ] MySQL access to your central backend database
- [ ] AWS IAM role with proper permissions attached to EC2 instances
- [ ] Agent v4.0.0 installed and running
- [ ] Central backend (final-ml) deployed and accessible

## Step 1: Apply Database Migration

### 1.1 Locate the Migration File

The migration file exists in both repositories:
- Central backend: `/tmp/final-ml/database/migrations/add_termination_tracking.sql`
- Agent repo: `/home/user/agent-v2/database/migrations/add_termination_tracking.sql`

Both files are identical - use either one.

### 1.2 Review the Migration

```sql
-- Adds termination tracking to instances table
ALTER TABLE instances
    ADD COLUMN IF NOT EXISTS termination_attempted_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS termination_confirmed BOOLEAN DEFAULT FALSE;

-- Adds termination tracking to replica_instances table
ALTER TABLE replica_instances
    ADD COLUMN IF NOT EXISTS termination_attempted_at TIMESTAMP NULL,
    ADD COLUMN IF NOT EXISTS termination_confirmed BOOLEAN DEFAULT FALSE;

-- Creates indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_instances_zombie_termination
    ON instances(instance_status, termination_attempted_at, region);
CREATE INDEX IF NOT EXISTS idx_replicas_termination
    ON replica_instances(status, termination_attempted_at, agent_id);
```

### 1.3 Apply the Migration

**Option A: Direct MySQL Connection**
```bash
# Connect to your MySQL database
mysql -h <your-db-host> -u <username> -p <database_name>

# Run the migration
mysql> source /tmp/final-ml/database/migrations/add_termination_tracking.sql;

# Verify columns were added
mysql> DESCRIBE instances;
mysql> DESCRIBE replica_instances;
```

**Option B: Remote MySQL (if you have the file)**
```bash
mysql -h <your-db-host> -u <username> -p <database_name> < /tmp/final-ml/database/migrations/add_termination_tracking.sql
```

**Option C: Via phpMyAdmin or MySQL Workbench**
1. Open your database management tool
2. Select your database
3. Copy the SQL from the migration file
4. Execute the SQL

### 1.4 Verify Migration Success

Run these queries to confirm:

```sql
-- Check instances table has new columns
SELECT COUNT(*) as has_columns
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '<your_database>'
  AND TABLE_NAME = 'instances'
  AND COLUMN_NAME IN ('termination_attempted_at', 'termination_confirmed');
-- Should return: has_columns = 2

-- Check replica_instances table has new columns
SELECT COUNT(*) as has_columns
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '<your_database>'
  AND TABLE_NAME = 'replica_instances'
  AND COLUMN_NAME IN ('termination_attempted_at', 'termination_confirmed');
-- Should return: has_columns = 2

-- Check indexes were created
SHOW INDEX FROM instances WHERE Key_name = 'idx_instances_zombie_termination';
SHOW INDEX FROM replica_instances WHERE Key_name = 'idx_replicas_termination';
```

## Step 2: Verify AWS IAM Permissions

### 2.1 Check Current IAM Role

On your EC2 instance where the agent runs:

```bash
# Get the IAM role attached to the instance
aws sts get-caller-identity

# Should show something like:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:sts::123456789012:assumed-role/SpotOptimizer/i-xxx"
# }
```

### 2.2 Verify Termination Permission

Test if you can terminate instances (dry-run):

```bash
# Create a test instance (or use an existing one)
TEST_INSTANCE_ID="i-xxxxxxxxx"

# Try a dry-run termination
aws ec2 terminate-instances --instance-ids $TEST_INSTANCE_ID --dry-run

# Expected responses:
# ✅ SUCCESS: "An error occurred (DryRunOperation): Request would have succeeded"
# ❌ FAILURE: "An error occurred (UnauthorizedOperation): You are not authorized"
```

### 2.3 Verify Instance Tagging

Check if your instances have the required tag:

```bash
# Check current instance tags
aws ec2 describe-instances \
  --instance-ids $(ec2-metadata --instance-id | cut -d' ' -f2) \
  --query 'Reservations[0].Instances[0].Tags[?Key==`ManagedBy`].Value' \
  --output text

# Should output: SpotOptimizer
```

### 2.4 Apply IAM Policy (If Needed)

If permissions are missing, apply this policy to your IAM role:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SpotOptimizerTerminatePermissions",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:TerminateInstances"
            ],
            "Resource": "arn:aws:ec2:*:*:instance/*",
            "Condition": {
                "StringEquals": {
                    "ec2:ResourceTag/ManagedBy": "SpotOptimizer"
                }
            }
        }
    ]
}
```

**To apply**:
1. Go to AWS IAM Console
2. Find your IAM role (e.g., `SpotOptimizer-Role`)
3. Attach an inline policy or add to existing policy
4. Wait 5-10 seconds for permissions to propagate

## Step 3: Verify Agent Configuration

### 3.1 Check Agent Is Running

```bash
# Check if agent process is running
ps aux | grep spot_optimizer_agent

# Check agent logs
tail -f /var/log/spot-optimizer-agent.log
```

### 3.2 Verify Configuration

Check the agent's environment variables:

```bash
# Check SERVER_URL points to your backend
echo $SPOT_OPTIMIZER_SERVER_URL

# Check CLIENT_TOKEN is set
echo $SPOT_OPTIMIZER_CLIENT_TOKEN | cut -c1-10
# Should show: token-abcd (first 10 chars)

# Verify connection to backend
curl -H "Authorization: Bearer $SPOT_OPTIMIZER_CLIENT_TOKEN" \
     "$SPOT_OPTIMIZER_SERVER_URL/api/agents/<agent_id>/config"
# Should return JSON with configuration
```

### 3.3 Check Cleanup Worker Status

Look for cleanup worker activity in logs:

```bash
# Search for cleanup worker logs
grep -i "cleanup worker" /var/log/spot-optimizer-agent.log | tail -20

# Search for termination activity
grep -i "instances to terminate" /var/log/spot-optimizer-agent.log | tail -20
```

Expected log lines:
```
[Cleanup Worker] Checking for instances to terminate...
[Cleanup Worker] Fetched 0 instances to terminate
[Cleanup Worker] Auto-terminate enabled: True
```

## Step 4: Test Termination Workflow

### 4.1 Prepare Test Environment

**IMPORTANT**: Use a test/dev environment for this, not production!

```bash
# Set shorter wait time for testing (optional)
# In your database:
UPDATE agents SET terminate_wait_seconds = 30 WHERE id = '<agent_id>';
UPDATE agents SET auto_terminate_enabled = TRUE WHERE id = '<agent_id>';
```

### 4.2 Create a Test Zombie Instance

You have two options:

**Option A: Mark Existing Instance as Zombie**
```sql
-- Pick an instance that you're OK terminating
UPDATE instances
SET instance_status = 'zombie',
    is_active = FALSE,
    updated_at = DATE_SUB(NOW(), INTERVAL 1 MINUTE)
WHERE id = '<test_instance_id>';

-- Verify it shows up in termination queue
SELECT
    i.id,
    i.instance_status,
    i.is_active,
    TIMESTAMPDIFF(SECOND, i.updated_at, NOW()) as seconds_waiting,
    a.terminate_wait_seconds
FROM instances i
JOIN agents a ON i.agent_id = a.id
WHERE i.instance_status = 'zombie';
```

**Option B: Launch a Test Instance**
```bash
# Launch a small test instance with proper tags
aws ec2 run-instances \
  --image-id ami-xxxxxxxx \
  --instance-type t3.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=SpotOptimizer-Test},{Key=ManagedBy,Value=SpotOptimizer}]' \
  --count 1

# Get the instance ID
TEST_INSTANCE_ID="i-xxxxxxxxx"

# Wait for it to be running
aws ec2 wait instance-running --instance-ids $TEST_INSTANCE_ID

# Mark it as zombie in database
# (Use SQL from Option A above)
```

### 4.3 Monitor Termination Process

Open multiple terminal windows to watch different parts:

**Terminal 1: Agent Logs**
```bash
tail -f /var/log/spot-optimizer-agent.log | grep -i "terminate"
```

**Terminal 2: AWS Instance Status**
```bash
# Watch instance state in AWS
watch -n 5 'aws ec2 describe-instances --instance-ids <test_instance_id> --query "Reservations[0].Instances[0].State.Name" --output text'
```

**Terminal 3: Database Status**
```bash
# Watch database updates
watch -n 5 "mysql -u <user> -p<pass> <db> -e \"SELECT id, instance_status, termination_attempted_at, termination_confirmed FROM instances WHERE id='<test_instance_id>'\""
```

**Terminal 4: Backend API Calls**
```bash
# Monitor backend logs (if you have access)
tail -f /var/log/spot-optimizer-backend.log | grep -i "termination"
```

### 4.4 Expected Timeline

| Time | Event | Location | Status |
|------|-------|----------|--------|
| T+0s | Instance marked as zombie | Database | `instance_status='zombie'` |
| T+30s | Wait time expires | - | Ready for termination |
| T+0-60s | Agent polls backend | Agent | Fetches termination list |
| T+1-3s | Agent terminates instance | AWS | `ec2.terminate_instances()` |
| T+1-3s | Agent reports success | Backend | API call |
| T+1-3s | Backend updates database | Database | `termination_confirmed=TRUE` |
| T+1-10s | AWS processes termination | AWS | State: `running` → `terminating` |
| T+10-60s | AWS completes termination | AWS | State: `terminated` |

### 4.5 Verify Success

After the test, verify all steps completed:

**1. Check Database**
```sql
SELECT
    id,
    instance_status,
    is_active,
    terminated_at,
    termination_attempted_at,
    termination_confirmed
FROM instances
WHERE id = '<test_instance_id>';

-- Expected result:
-- instance_status: 'terminated'
-- is_active: FALSE (0)
-- terminated_at: <timestamp>
-- termination_attempted_at: <timestamp>
-- termination_confirmed: TRUE (1)
```

**2. Check AWS**
```bash
aws ec2 describe-instances --instance-ids <test_instance_id> \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text

# Expected: terminated
```

**3. Check System Events**
```sql
SELECT
    event_type,
    severity,
    agent_id,
    message,
    created_at
FROM system_events
WHERE message LIKE '%<test_instance_id>%'
ORDER BY created_at DESC
LIMIT 5;

-- Expected: Event with type 'instance_terminated' and severity 'info'
```

**4. Check Agent Logs**
```bash
grep -i "<test_instance_id>" /var/log/spot-optimizer-agent.log | tail -20

# Look for lines like:
# ✅ INSTANCE <test_instance_id> TERMINATED SUCCESSFULLY
# Successfully terminated EC2 instance <test_instance_id>
```

## Step 5: Production Deployment

Once testing is successful, deploy to production:

### 5.1 Restore Production Settings

```sql
-- Set production wait times (5 minutes default)
UPDATE agents SET terminate_wait_seconds = 300;

-- Enable auto-terminate for production agents
UPDATE agents SET auto_terminate_enabled = TRUE;

-- Or set defaults at client level
UPDATE clients SET default_terminate_wait_seconds = 300;
UPDATE clients SET default_auto_terminate = TRUE;
```

### 5.2 Monitor Initial Production Run

For the first few hours, monitor closely:

```bash
# Watch termination activity
tail -f /var/log/spot-optimizer-agent.log | grep -E "(terminate|zombie)"

# Count pending terminations
mysql -u <user> -p -e "SELECT COUNT(*) as zombie_count FROM instances WHERE instance_status='zombie' AND is_active=FALSE"

# Check success rate
mysql -u <user> -p -e "
SELECT
    DATE(created_at) as date,
    event_type,
    COUNT(*) as count
FROM system_events
WHERE event_type IN ('instance_terminated', 'instance_termination_failed')
    AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
GROUP BY DATE(created_at), event_type
ORDER BY date DESC;
"
```

### 5.3 Set Up Alerts (Recommended)

Create monitoring alerts for:

**1. Failed Terminations**
```sql
-- Check for repeated failures
SELECT
    instance_id,
    COUNT(*) as failure_count,
    MAX(created_at) as last_failure
FROM system_events
WHERE event_type = 'instance_termination_failed'
    AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
GROUP BY instance_id
HAVING failure_count > 3;
```

**2. Stuck Zombies**
```sql
-- Instances stuck as zombies for too long
SELECT
    id,
    instance_status,
    TIMESTAMPDIFF(MINUTE, updated_at, NOW()) as minutes_stuck,
    termination_attempted_at,
    termination_confirmed
FROM instances
WHERE instance_status = 'zombie'
    AND is_active = FALSE
    AND updated_at < DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY updated_at ASC;
```

**3. IAM Permission Errors**
```sql
-- Check for permission errors
SELECT *
FROM system_events
WHERE message LIKE '%UnauthorizedOperation%'
    OR message LIKE '%IAM%'
    OR message LIKE '%permission%'
    AND created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR);
```

## Troubleshooting Guide

### Issue: Migration Fails with "Column already exists"

**Cause**: Migration was already applied

**Solution**: This is fine! The `IF NOT EXISTS` clause prevents errors. Verify columns exist:
```sql
DESCRIBE instances;
```

### Issue: Agent Logs "Failed to fetch instances to terminate"

**Cause**: Backend API not responding or authentication issue

**Solution**:
1. Check `CLIENT_TOKEN` is correct
2. Verify backend is running and accessible
3. Check backend logs for errors
4. Test API manually:
   ```bash
   curl -H "Authorization: Bearer $SPOT_OPTIMIZER_CLIENT_TOKEN" \
        "$SPOT_OPTIMIZER_SERVER_URL/api/agents/<agent_id>/instances-to-terminate"
   ```

### Issue: "UnauthorizedOperation" when terminating

**Cause**: IAM permissions missing or instance doesn't have required tag

**Solution**:
1. Verify IAM policy includes `ec2:TerminateInstances`
2. Check instance has `ManagedBy: SpotOptimizer` tag:
   ```bash
   aws ec2 describe-tags --filters "Name=resource-id,Values=<instance_id>" "Name=key,Values=ManagedBy"
   ```
3. If tag is missing, add it:
   ```bash
   aws ec2 create-tags --resources <instance_id> --tags Key=ManagedBy,Value=SpotOptimizer
   ```

### Issue: Instance terminated in AWS but database shows `termination_confirmed=FALSE`

**Cause**: Agent successfully terminated but failed to report to backend

**Solution**:
1. Manually update database:
   ```sql
   UPDATE instances
   SET termination_confirmed = TRUE,
       terminated_at = NOW()
   WHERE id = '<instance_id>';
   ```
2. Check backend connectivity
3. Check backend logs for API errors

### Issue: Zombie instances not being terminated

**Cause**: Multiple possibilities

**Solution**: Check each component:

1. **Is auto_terminate enabled?**
   ```sql
   SELECT auto_terminate_enabled FROM agents WHERE id = '<agent_id>';
   ```

2. **Has wait time passed?**
   ```sql
   SELECT
       id,
       TIMESTAMPDIFF(SECOND, updated_at, NOW()) as seconds_since_zombie,
       (SELECT terminate_wait_seconds FROM agents WHERE id = i.agent_id) as required_wait
   FROM instances i
   WHERE instance_status = 'zombie';
   ```

3. **Was termination recently attempted?**
   ```sql
   SELECT
       id,
       termination_attempted_at,
       TIMESTAMPDIFF(MINUTE, termination_attempted_at, NOW()) as minutes_since_attempt
   FROM instances
   WHERE instance_status = 'zombie'
       AND termination_attempted_at IS NOT NULL;
   ```
   *Note: 5-minute cooldown between attempts*

4. **Is the cleanup worker running?**
   ```bash
   grep "Cleanup Worker" /var/log/spot-optimizer-agent.log | tail -5
   ```

## Performance Tuning

### Adjust Polling Interval

If you need faster termination detection, modify the agent config:

**File**: `/home/user/agent-v2/backend/spot_optimizer_agent.py`

```python
# Line ~70
CLEANUP_CHECK_INTERVAL = 60  # Change to 30 for faster polling
```

**Restart agent** after change:
```bash
sudo systemctl restart spot-optimizer-agent
```

### Adjust Wait Time

For faster cleanup (less cost):
```sql
-- Shorter wait time (2 minutes)
UPDATE agents SET terminate_wait_seconds = 120;

-- Longer wait time (more safety)
UPDATE agents SET terminate_wait_seconds = 600;  -- 10 minutes
```

### Database Query Optimization

If you have thousands of instances, add these additional indexes:

```sql
-- Optimize zombie lookups
CREATE INDEX idx_instances_status_active ON instances(instance_status, is_active);

-- Optimize agent-specific queries
CREATE INDEX idx_instances_agent_status ON instances(agent_id, instance_status);

-- Analyze tables
ANALYZE TABLE instances;
ANALYZE TABLE replica_instances;
```

## Monitoring Dashboard

### Key Metrics to Track

1. **Termination Rate**
   ```sql
   -- Terminations per hour
   SELECT
       DATE_FORMAT(created_at, '%Y-%m-%d %H:00') as hour,
       COUNT(*) as terminations
   FROM system_events
   WHERE event_type = 'instance_terminated'
       AND created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
   GROUP BY hour
   ORDER BY hour DESC;
   ```

2. **Success Rate**
   ```sql
   -- Success vs failure rate
   SELECT
       event_type,
       COUNT(*) as count,
       (COUNT(*) * 100.0 / (SELECT COUNT(*) FROM system_events WHERE event_type IN ('instance_terminated', 'instance_termination_failed'))) as percentage
   FROM system_events
   WHERE event_type IN ('instance_terminated', 'instance_termination_failed')
       AND created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
   GROUP BY event_type;
   ```

3. **Average Termination Latency**
   ```sql
   -- Time from zombie to terminated
   SELECT
       AVG(TIMESTAMPDIFF(SECOND, updated_at, terminated_at)) as avg_seconds,
       MIN(TIMESTAMPDIFF(SECOND, updated_at, terminated_at)) as min_seconds,
       MAX(TIMESTAMPDIFF(SECOND, updated_at, terminated_at)) as max_seconds
   FROM instances
   WHERE instance_status = 'terminated'
       AND terminated_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR);
   ```

4. **Current Zombie Count**
   ```sql
   -- How many zombies are waiting
   SELECT
       COUNT(*) as zombie_count,
       AVG(TIMESTAMPDIFF(SECOND, updated_at, NOW())) as avg_wait_seconds
   FROM instances
   WHERE instance_status = 'zombie'
       AND is_active = FALSE;
   ```

## Next Steps

After successful deployment:

1. ✅ Monitor for 24 hours to ensure stability
2. ✅ Set up automated alerts for failures
3. ✅ Document any environment-specific configurations
4. ✅ Train team on troubleshooting procedures
5. ✅ Schedule regular audits of zombie instances

## Support

If you encounter issues not covered in this guide:

1. Check agent logs: `/var/log/spot-optimizer-agent.log`
2. Check backend logs: `/var/log/spot-optimizer-backend.log`
3. Review system events: `SELECT * FROM system_events ORDER BY created_at DESC LIMIT 50;`
4. Contact support with:
   - Agent version
   - Error messages from logs
   - Instance ID and status from database
   - AWS error codes (if any)

## Summary

You've now completed:
- ✅ Database migration for termination tracking
- ✅ AWS IAM permission verification
- ✅ Agent configuration verification
- ✅ End-to-end termination workflow testing
- ✅ Production deployment and monitoring setup

Your AWS Spot Optimizer now has full command over AWS instance termination with proper tracking and error handling!
