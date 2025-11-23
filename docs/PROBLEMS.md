# Known Problems and Solutions

This document lists common issues encountered with the AWS Spot Optimizer and their solutions.

## Agent Issues

### 1. Agent Not Registering with Server

**Symptoms:**
- Agent logs show "Registration failed - no response from server"
- Agent keeps retrying but never connects

**Possible Causes & Solutions:**

1. **Server URL incorrect**
   ```bash
   # Check configuration
   cat /etc/spot-optimizer/agent.env

   # Verify server is reachable
   curl -v https://your-server/health
   ```

2. **Client token invalid**
   - Get a new token from admin dashboard
   - Update `/etc/spot-optimizer/agent.env`

3. **Network/firewall issues**
   ```bash
   # Check outbound connectivity
   nc -zv your-server 443

   # Check security group allows outbound HTTPS
   ```

4. **SSL certificate issues**
   ```bash
   # Test with verbose SSL output
   curl -v https://your-server/health
   ```

---

### 2. Switch Commands Not Executing

**Symptoms:**
- Commands show as pending in dashboard
- Agent logs show no command execution

**Possible Causes & Solutions:**

1. **Agent is disabled**
   ```bash
   # Check agent config
   curl -H "Authorization: Bearer $TOKEN" https://server/api/agents/$AGENT_ID/config
   ```
   Solution: Enable agent from dashboard

2. **Command polling not working**
   - Check logs for "Checking for pending commands"
   - Verify `PENDING_COMMANDS_CHECK_INTERVAL` is set

3. **IAM permissions missing**
   ```bash
   # Test EC2 permissions
   aws ec2 describe-instances --max-items 1
   aws ec2 run-instances --dry-run ...
   ```

---

### 3. Price Data Not Being Collected

**Symptoms:**
- Dashboard shows $0 prices
- Logs show "No spot pools found"

**Possible Causes & Solutions:**

1. **Region mismatch**
   ```bash
   # Verify region in config
   grep AWS_REGION /etc/spot-optimizer/agent.env

   # Test spot price API
   aws ec2 describe-spot-price-history \
     --instance-types t3.medium \
     --max-items 1 \
     --region us-east-1
   ```

2. **Pricing API access**
   - Ensure IAM policy includes `pricing:GetProducts`
   - Note: Pricing API only works from us-east-1

3. **Instance type not available in region**
   - Some instance types aren't available in all AZs

---

### 4. Termination Notice Not Detected

**Symptoms:**
- Instance terminated without warning
- No emergency replica created

**Possible Causes & Solutions:**

1. **Instance not running on spot**
   ```bash
   # Check instance lifecycle
   aws ec2 describe-instances --instance-ids i-xxx \
     --query 'Reservations[].Instances[].InstanceLifecycle'
   ```

2. **Check interval too long**
   - Default `TERMINATION_CHECK_INTERVAL` is 5 seconds
   - AWS gives 2-minute warning, so this should be sufficient

3. **Metadata service issues**
   ```bash
   # Test metadata access
   TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
     -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
   curl -H "X-aws-ec2-metadata-token: $TOKEN" \
     http://169.254.169.254/latest/meta-data/spot/instance-action
   ```

---

### 5. Cleanup Not Running

**Symptoms:**
- Old snapshots/AMIs accumulating
- No cleanup logs in agent output

**Possible Causes & Solutions:**

1. **Check cleanup interval**
   - Default is 3600 seconds (1 hour)
   - First cleanup runs after 60 seconds

2. **IAM permissions for cleanup**
   ```bash
   # Test snapshot deletion
   aws ec2 delete-snapshot --snapshot-id snap-xxx --dry-run

   # Test AMI deregistration
   aws ec2 deregister-image --image-id ami-xxx --dry-run
   ```

3. **No SpotOptimizer tags**
   - Cleanup only targets resources with `ManagedBy=SpotOptimizer` tag
   - Old resources without tags won't be cleaned

---

## Backend/Server Issues

### 6. Duplicate Agents in Dashboard

**Symptoms:**
- Same instance appears multiple times
- Different agent IDs for same logical entity

**Solution:**
Set `LOGICAL_AGENT_ID` environment variable to persist identity:
```bash
echo "LOGICAL_AGENT_ID=my-web-server" >> /etc/spot-optimizer/agent.env
sudo systemctl restart spot-optimizer-agent
```

---

### 7. Switch Reports Not Recording

**Symptoms:**
- Switches execute successfully
- No records in switch history

**Possible Causes:**
1. Backend endpoint not implemented - see `missing-backend-server/MISSING_FEATURES.md`
2. Database schema missing - see `missing-backend-server/REQUIRED_SCHEMA.sql`

---

### 8. Savings Not Calculating

**Symptoms:**
- Dashboard shows $0 savings
- Switch history exists but no savings data

**Solution:**
Implement the savings calculation scheduled job in the backend. See `missing-backend-server/REQUIRED_SCHEMA.sql` for the stored procedure.

---

## Frontend/Dashboard Issues

### 9. Cannot Login to Dashboard

**Symptoms:**
- "Invalid client token" error
- Page redirects to login

**Solutions:**

1. **Verify token**
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://backend-server/api/client/validate
   ```

2. **Backend endpoint missing**
   - Implement `/api/client/validate` endpoint

3. **Session issues**
   - Clear browser cookies
   - Check Flask secret key is set

---

### 10. Dashboard Not Loading Data

**Symptoms:**
- Dashboard shows 0 for all stats
- Network tab shows 500 errors

**Solutions:**

1. **Check backend connectivity**
   ```bash
   curl https://backend-server/api/client/CLIENT_ID
   ```

2. **Check CORS settings** on backend if different origins

3. **Check backend logs** for actual errors

---

## AWS-Specific Issues

### 11. Spot Instance Launch Failures

**Error:** `InsufficientInstanceCapacity`

**Solutions:**
1. Try different availability zone
2. Try different instance type
3. Use spot fleet with multiple instance types

---

### 12. AMI Creation Taking Too Long

**Symptoms:**
- Switch process stuck at "Creating AMI"
- Timeouts during switch

**Solutions:**
1. Use `NoReboot=True` for faster AMI creation
2. Reduce root volume size
3. Consider using snapshots instead of full AMIs

---

### 13. Cross-Region Pricing API Failures

**Error:** `Could not connect to the endpoint URL`

**Cause:** AWS Pricing API only available in us-east-1 and ap-south-1

**Solution:** Agent already handles this by using us-east-1 for pricing API calls.

---

## Performance Issues

### 14. High CPU Usage

**Symptoms:**
- Agent using excessive CPU
- System slowdown

**Solutions:**
1. Increase check intervals:
   ```env
   HEARTBEAT_INTERVAL=60
   PENDING_COMMANDS_CHECK_INTERVAL=30
   ```

2. Check for log spam - reduce logging level

---

### 15. Memory Leaks

**Symptoms:**
- Memory usage growing over time
- OOM killer terminating agent

**Solutions:**
1. Update to latest agent version
2. Restart agent periodically via cron:
   ```cron
   0 4 * * * systemctl restart spot-optimizer-agent
   ```

---

## Debugging Tips

### Enable Debug Logging

Edit the agent file or set environment variable:
```python
logging.basicConfig(level=logging.DEBUG, ...)
```

### Check All Logs

```bash
# Agent log
tail -f /var/log/spot-optimizer/agent.log

# System journal
journalctl -u spot-optimizer-agent -f

# AWS CLI debug
aws ec2 describe-instances --debug
```

### Test Components Individually

```bash
# Test server connectivity
curl -v https://server/health

# Test AWS credentials
aws sts get-caller-identity

# Test EC2 API
aws ec2 describe-instances --max-items 1

# Test pricing API
aws pricing get-products --service-code AmazonEC2 --max-items 1 --region us-east-1

# Test metadata service
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id
```

---

## Getting Help

1. Check agent logs first: `spot-agent-logs`
2. Review this document for similar issues
3. Open an issue with:
   - Agent version
   - Relevant log excerpts
   - Steps to reproduce
   - Expected vs actual behavior
