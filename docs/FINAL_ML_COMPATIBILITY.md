# Final-ML Repository Compatibility Guide

This document details the compatibility analysis between the `agent-v2` repository and the reference `final-ml` repository (https://github.com/atharva0608/final-ml.git).

## Executive Summary

**Good News:** The agent implementations are **100% identical**. Both repositories use the same `spot_optimizer_agent.py` (v4.0.0, 1,777 lines).

**Main Difference:** The backend API implementation:
- **agent-v2**: Uses a simple proxy server that forwards requests to a remote backend
- **final-ml**: Has a complete, production-ready backend implementation

## Repository Comparison

### 1. Agent Implementation ✅ IDENTICAL

Both repositories have the exact same agent code:

| File | agent-v2 | final-ml | Status |
|------|----------|----------|--------|
| Main Agent | `/backend/spot_optimizer_agent.py` | `/agent/spot_optimizer_agent.py` | ✅ Identical |
| Legacy Agent | `/backend/spot_agent_production_v2_final.py` | `/agent/spot_agent_production_v2_final.py` | ✅ Identical |
| Version | 4.0.0 | 4.0.0 | ✅ Same |
| Lines | 1,777 | 1,777 | ✅ Same |

**Conclusion:** No agent upgrades needed. The agents are already fully compatible.

---

### 2. API Server Implementation ⚠️ MAJOR DIFFERENCE

#### agent-v2 API Server
**File:** `/frontend/api_server.py` (250 lines)
- **Type:** Simple HTTP proxy
- **Function:** Forwards all requests to remote backend at `BACKEND_URL`
- **Endpoints:** Now has all 20+ endpoints (after our updates)
- **Business Logic:** None (just proxies)
- **Database:** No direct access

#### final-ml Backend
**File:** `/backend/backend.py` (7,058 lines)
- **Type:** Complete Flask backend
- **Function:** Full business logic implementation
- **Features:**
  - Direct database access with connection pooling
  - ML decision engine integration
  - Smart Emergency Fallback (SEF) system
  - Replica coordination
  - File upload support (ML models, decision engines)
  - Background job scheduling (APScheduler)
  - Comprehensive validation and error handling

---

### 3. Database Schema ⚠️ SIGNIFICANT UPGRADE

#### Current Schema (agent-v2)
Located in: `/missing-backend-server/REQUIRED_SCHEMA.sql` (minimal schema notes)

#### Final-ML Schema
**File:** `/home/user/final-ml-reference/database/schema.sql` (2,210 lines)

**Complete schema with:**
- **40+ tables** for full system operation
- **17 stored procedures** for common operations
- **5 views** for complex queries
- **4 scheduled events** for automated tasks
- **Advanced features:**
  - Pricing data deduplication
  - Interpolated pricing for gap filling
  - ML model registry
  - Spot interruption event tracking (with ML training features)
  - Pool reliability metrics
  - Comprehensive replica management
  - Cost tracking and savings calculation
  - Audit logging

#### Key Tables in Final-ML Schema

**Core System:**
- `clients` - Client accounts
- `agents` - Agent registrations with logical identity
- `agent_configs` - Per-agent thresholds and limits
- `commands` - Priority-based command queue
- `instances` - Instance records
- `switches` - Detailed switch history with timing

**Pricing & Pools:**
- `spot_pools` - Available spot pools
- `spot_price_snapshots` - Historical spot prices
- `ondemand_price_snapshots` - Historical on-demand prices
- `pricing_reports` - Agent-submitted pricing data
- `pricing_snapshots_clean` - Deduplicated time-bucketed data
- `pricing_snapshots_interpolated` - Gap-filled data

**Replicas:**
- `replica_instances` - Replica tracking with sync status
- `replica_cost_log` - Replica cost tracking

**ML & Decision Engine:**
- `model_registry` - ML model versions
- `model_upload_sessions` - Model upload tracking
- `model_predictions` - ML predictions and risk scores
- `risk_scores` - Decision history
- `decision_engine_log` - Audit trail

**Emergency Handling:**
- `spot_interruption_events` - Termination and rebalance events (with ML features)
- `termination_events` - Event resolution workflow
- `pool_reliability_metrics` - Pool interruption tracking

**Cost & Savings:**
- `cost_records` - Cost tracking
- `client_savings_monthly` - Monthly savings aggregation
- `client_savings_daily` - Daily savings aggregation
- `savings_snapshots` - Historical savings tracking

**Agent Monitoring:**
- `cleanup_logs` - Agent cleanup operations
- `agent_health_metrics` - Agent performance tracking

**System:**
- `system_events` - Event logging
- `notifications` - User notifications
- `audit_logs` - Comprehensive audit trail

---

### 4. API Endpoints Comparison

#### Recently Added to agent-v2 (Today's Updates) ✅

We've added all missing endpoints to the API proxy server:

**Agent Operations:**
- `POST /api/agents/register`
- `POST /api/agents/{id}/heartbeat`
- `GET /api/agents/{id}/config`
- `GET /api/agents/{id}/pending-commands`
- `POST /api/agents/{id}/commands/{id}/executed`

**Reporting:**
- `POST /api/agents/{id}/pricing-report`
- `POST /api/agents/{id}/switch-report`
- `POST /api/agents/{id}/cleanup-report`

**Emergency:**
- `POST /api/agents/{id}/termination-imminent`
- `POST /api/agents/{id}/rebalance-recommendation`
- `POST /api/agents/{id}/create-emergency-replica`

**Replicas:**
- `GET /api/agents/{id}/replicas?status=launching`
- `GET /api/agents/{id}/replica-config`
- `PUT /api/agents/{id}/replicas/{id}`
- `POST /api/agents/{id}/replicas/{id}/status`

#### Endpoints Only in final-ml Backend

**Decision Engine:**
- `POST /api/agents/{id}/decide` - Get ML decision
- `GET /api/agents/{id}/switch-recommendation` - Get recommendation

**Admin Features:**
- `POST /api/admin/decision-engine/upload` - Upload new decision engine
- `POST /api/admin/ml-models/upload` - Upload ML models
- `POST /api/admin/ml-models/activate` - Activate model
- `POST /api/admin/ml-models/fallback` - Fallback to previous model

---

### 5. Special Features in final-ml Backend

#### Smart Emergency Fallback (SEF)
**File:** `/backend/smart_emergency_fallback.py` (1,213 lines)

**Key Features:**
1. **Data Quality Assurance**
   - Deduplicates pricing data from primary + replicas
   - Averages discrepant data
   - Detects gaps (>10 minutes)
   - Interpolates missing data points

2. **Emergency Replica Management**
   - Calculates interruption risk
   - Finds safest/cheapest pool
   - Creates replicas automatically
   - Handles rebalance recommendations

3. **Termination Handling**
   - Promotes replica in <15 seconds
   - Falls back to emergency snapshot
   - Zero-downtime failover

4. **Manual Replica Mode**
   - Continuous hot standby
   - User-controlled switching
   - Auto-creates new replica after switch

#### ML-Based Decision Engine
**File:** `/backend/decision_engines/ml_based_engine.py`

**Features:**
- Pluggable architecture
- Supports multiple model types (.pkl, .h5, .pth, .onnx)
- Falls back to rule-based logic
- Logs all decisions for audit

**Rule-Based Fallback:**
- >80% of on-demand price → switch to on-demand
- >30% potential savings → recommend spot

---

## Current Setup Analysis

### What Works Now ✅

1. **Agent Installation**
   - Agent code is identical to final-ml
   - All worker threads functioning
   - Heartbeat, pricing reports, cleanup operations working

2. **API Proxy Server**
   - All required endpoints are now defined
   - Forwards requests to backend correctly
   - Handles query parameters (e.g., `?status=launching`)

3. **Connection Flow**
   ```
   Agent → API Proxy (localhost:5000) → Backend (100.28.125.108)
   ```

### What's Missing ⚠️

1. **Backend Implementation**
   - The backend at `100.28.125.108` may not implement all endpoints
   - Connection errors in logs indicate missing endpoints:
     - `/api/agents/{id}/pending-commands`
     - `/api/agents/{id}/replicas?status=launching`

2. **Database**
   - Need complete schema from final-ml
   - Missing tables for replicas, ML models, interruption events

3. **ML Models**
   - No decision engine loaded
   - No ML models uploaded

---

## Upgrade Path

### Option 1: Use Final-ML Backend (Recommended)

**Steps:**

1. **Deploy final-ml backend**
   ```bash
   # Clone final-ml
   git clone https://github.com/atharva0608/final-ml.git
   cd final-ml

   # Set up database
   mysql -u root -p < database/schema.sql

   # Configure environment
   cp .env.example .env
   # Edit .env with database credentials, client tokens, etc.

   # Install dependencies
   pip install -r requirements.txt

   # Run backend
   python backend/backend.py
   ```

2. **Update agent-v2 API proxy**
   ```bash
   # Edit /home/user/agent-v2/frontend/api_server.py
   # Change BACKEND_URL to point to final-ml backend
   BACKEND_URL = 'http://your-final-ml-backend:5000'
   ```

3. **Restart services**
   ```bash
   # On agent instance
   sudo systemctl restart spot-optimizer-agent
   sudo systemctl restart spot-optimizer-api-server
   ```

### Option 2: Implement Missing Backend Endpoints

**Required Work:**

1. **Database Setup**
   - Run complete schema from final-ml
   - Set up connection pooling
   - Configure scheduled events

2. **Implement Core Endpoints**
   - Agent registration and heartbeat handlers
   - Pricing report processors
   - Command queue management
   - Replica coordination

3. **Add SEF System** (optional but recommended)
   - Data deduplication
   - Gap filling
   - Emergency replica coordination

4. **Add Decision Engine** (optional)
   - Rule-based or ML-based
   - Model registry
   - Prediction logging

**Estimated Effort:** 2-4 weeks of development

### Option 3: Hybrid Approach

1. **Use final-ml backend for production**
2. **Keep agent-v2 as deployment repository**
3. **Sync agent code when needed**

---

## Migration Checklist

### Database Migration

- [ ] Export current data (if any)
- [ ] Create database with final-ml schema
- [ ] Migrate client records
- [ ] Migrate agent registrations
- [ ] Test database connections

### Backend Deployment

- [ ] Deploy final-ml backend server
- [ ] Configure environment variables
- [ ] Set up client tokens
- [ ] Test API endpoints
- [ ] Configure SSL/TLS

### Agent Configuration

- [ ] Update agent environment variables
- [ ] Point to new backend URL
- [ ] Test agent registration
- [ ] Verify heartbeat connectivity
- [ ] Monitor agent logs

### Frontend Update

- [ ] Update API proxy backend URL
- [ ] Test all dashboard endpoints
- [ ] Verify data display
- [ ] Test user actions (switch, replicas)

### Testing

- [ ] Agent registration works
- [ ] Heartbeat updates status
- [ ] Pricing reports received
- [ ] Commands executed
- [ ] Replicas can be created
- [ ] Switch operations complete
- [ ] Dashboard displays data

---

## Key Differences Summary

| Feature | agent-v2 | final-ml | Action Needed |
|---------|----------|----------|---------------|
| Agent Code | v4.0.0 ✅ | v4.0.0 ✅ | None |
| API Endpoints | 20+ (proxy) ✅ | 40+ (full) | Use final-ml backend |
| Database Schema | Minimal | Complete (40+ tables) | Deploy final-ml schema |
| Business Logic | None (proxy) | Full (7,058 lines) | Use final-ml backend |
| ML Models | Not supported | Full support | Use final-ml backend |
| SEF System | Not implemented | Implemented (1,213 lines) | Use final-ml backend |
| Background Jobs | None | APScheduler | Use final-ml backend |
| File Uploads | Not supported | Supported | Use final-ml backend |

---

## Configuration Reference

### Agent Environment Variables

Both repositories use the same agent configuration:

```bash
# Server Connection
SPOT_OPTIMIZER_SERVER_URL=http://your-backend:5000
SPOT_OPTIMIZER_CLIENT_TOKEN=your-token-here

# Agent Identity
LOGICAL_AGENT_ID=my-server-01
AWS_REGION=us-east-1

# Timing (seconds)
HEARTBEAT_INTERVAL=30
PENDING_COMMANDS_CHECK_INTERVAL=15
PRICING_REPORT_INTERVAL=300

# Features
AUTO_TERMINATE_OLD_INSTANCE=true
REPLICA_ENABLED=false
CLEANUP_SNAPSHOTS_OLDER_THAN_DAYS=7
```

### Backend Environment Variables (final-ml)

```bash
# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=spot_optimizer
DB_USER=spot_user
DB_PASSWORD=your-password

# Server
FLASK_ENV=production
PORT=5000
SECRET_KEY=your-secret-key

# Decision Engine
DECISION_ENGINE_CLASS=decision_engines.ml_based_engine.MLBasedDecisionEngine
ML_MODELS_DIR=./models

# Features
ENABLE_SEF=true
ENABLE_ML_DECISIONS=true
```

---

## Troubleshooting

### Connection Errors in Agent Logs

**Symptom:**
```
Connection error: /api/agents/{id}/pending-commands
Connection error: /api/agents/{id}/replicas?status=launching
```

**Cause:** Backend at `100.28.125.108` doesn't implement these endpoints

**Solution:**
1. Deploy final-ml backend
2. Update `BACKEND_URL` in API proxy to point to final-ml backend
3. Restart services

### Agent Not Showing in Dashboard

**Cause:** Agent registration endpoint not working

**Check:**
1. Agent logs for registration success
2. Backend logs for received registration
3. Database for agent record
4. API proxy forwarding correctly

**Solution:** Ensure final-ml backend is running and accessible

### Pricing Data Not Displaying

**Cause:** Pricing report endpoint not storing data

**Check:**
1. Agent logs show "Pricing report sent"
2. Backend receives pricing reports
3. Database has `pricing_reports` table
4. Dashboard queries correct endpoints

---

## Recommendations

### Immediate (Today)
✅ **DONE:** Added all missing API endpoints to agent-v2 proxy

### Short-term (This Week)
1. **Deploy final-ml backend** on a server
2. **Run complete database schema**
3. **Update API proxy** to point to final-ml backend
4. **Test end-to-end flow**

### Medium-term (This Month)
1. **Upload ML models** for decision engine
2. **Enable SEF system** for emergency handling
3. **Configure replica management**
4. **Set up monitoring and alerting**

### Long-term
1. **Train custom ML models** on your interruption data
2. **Optimize decision thresholds** based on your workload
3. **Implement custom decision engines** if needed
4. **Scale backend** with load balancer if needed

---

## Next Steps

1. **Decide on deployment strategy:**
   - Option 1: Deploy final-ml backend (recommended)
   - Option 2: Implement missing features in agent-v2
   - Option 3: Hybrid approach

2. **Database setup:**
   - Create MySQL database
   - Run final-ml schema
   - Configure connection

3. **Backend deployment:**
   - Deploy final-ml backend.py
   - Configure environment
   - Test endpoints

4. **Agent configuration:**
   - Update backend URL
   - Restart agent
   - Monitor logs

5. **Verification:**
   - Check agent registration
   - Verify heartbeat
   - Test switch command
   - Monitor dashboard

---

## Contact & Support

For issues or questions:
1. Check agent logs: `/var/log/spot-optimizer/agent-error.log`
2. Check backend logs
3. Review database records
4. Test endpoints with curl:
   ```bash
   curl -H "Authorization: Bearer $TOKEN" \
        http://backend:5000/api/agents
   ```

---

## File Locations Reference

### agent-v2 Repository
- Agent: `/home/user/agent-v2/backend/spot_optimizer_agent.py`
- API Proxy: `/home/user/agent-v2/frontend/api_server.py`
- Documentation: `/home/user/agent-v2/docs/`
- Logs: `/var/log/spot-optimizer/`

### final-ml Repository (Reference)
- Agent: `/home/user/final-ml-reference/agent/spot_optimizer_agent.py`
- Backend: `/home/user/final-ml-reference/backend/backend.py`
- SEF: `/home/user/final-ml-reference/backend/smart_emergency_fallback.py`
- Schema: `/home/user/final-ml-reference/database/schema.sql`
- Docs: `/home/user/final-ml-reference/COMPREHENSIVE_DOCUMENTATION.md`

---

**Last Updated:** 2025-11-23
**Agent Version:** 4.0.0 (identical in both repos)
**Schema Version:** final-ml v5.1
