# 7-Day Pricing History Implementation Guide

## Overview

This document explains how to implement the 7-day pricing history feature that shows historical spot and on-demand pricing with interactive line charts.

## Features

✅ **Frontend (DONE):**
- Interactive line chart with filled areas
- Toggle lines on/off by clicking legend
- Auto-refresh every 12 hours
- Shows pricing for all 3 AZs + on-demand
- Average/Min/Max statistics
- Responsive design

✅ **API Proxy (DONE):**
- Endpoint: `GET /api/pricing/history?days=7&agent_id=xxx`
- Forwards to backend: `/api/client/pricing-history`

⚠️ **Backend (YOU NEED TO IMPLEMENT):**
- Database tables to store pricing history
- API endpoint to return pricing data
- Background job to aggregate pricing (every 12 hours)

---

## What the Agent Already Does ✅

The agent **already sends pricing data every 5 minutes** in this format:

```json
POST /api/agents/{agent_id}/pricing-report
{
  "instance": {
    "instance_id": "i-0265fbf8c56788998",
    "instance_type": "t3.medium",
    "region": "ap-south-1",
    "az": "ap-south-1a",
    "mode": "spot",
    "pool_id": "t3.medium.ap-south-1a"
  },
  "pricing": {
    "on_demand_price": 0.0416,
    "current_spot_price": 0.0132,
    "cheapest_pool": {
      "pool_id": "t3.medium.ap-south-1b",
      "price": 0.0128
    },
    "spot_pools": [
      {
        "pool_id": "t3.medium.ap-south-1a",
        "az": "ap-south-1a",
        "price": 0.0132,
        "instance_type": "t3.medium",
        "region": "ap-south-1"
      },
      {
        "pool_id": "t3.medium.ap-south-1b",
        "az": "ap-south-1b",
        "price": 0.0128,
        "instance_type": "t3.medium",
        "region": "ap-south-1"
      },
      {
        "pool_id": "t3.medium.ap-south-1c",
        "az": "ap-south-1c",
        "price": 0.0135,
        "instance_type": "t3.medium",
        "region": "ap-south-1"
      }
    ],
    "collected_at": "2025-11-23T14:30:00Z"
  }
}
```

**No agent changes needed!** The agent sends this data every 5 minutes (configurable via `PRICING_REPORT_INTERVAL`).

---

## Backend Implementation Required

### 1. Database Tables

You already have these tables in the final-ml schema:

#### A. `spot_price_snapshots` ✅ (Already exists)
```sql
CREATE TABLE IF NOT EXISTS spot_price_snapshots (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    pool_id VARCHAR(128) NOT NULL,
    price DECIMAL(10, 6) NOT NULL,
    captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_spot_snapshots_pool_time (pool_id, captured_at DESC),
    INDEX idx_spot_snapshots_captured (captured_at DESC),

    CONSTRAINT fk_spot_snapshots_pool FOREIGN KEY (pool_id)
        REFERENCES spot_pools(id) ON DELETE CASCADE
) ENGINE=InnoDB;
```

#### B. `ondemand_price_snapshots` ✅ (Already exists)
```sql
CREATE TABLE IF NOT EXISTS ondemand_price_snapshots (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    region VARCHAR(32) NOT NULL,
    instance_type VARCHAR(64) NOT NULL,
    price DECIMAL(10, 6) NOT NULL,
    captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_ondemand_snapshots_type_region_time (instance_type, region, captured_at DESC),
    INDEX idx_ondemand_snapshots_captured (captured_at DESC)
) ENGINE=InnoDB;
```

#### C. `pricing_reports` ✅ (Already exists)
Stores the raw pricing reports from agents:
```sql
CREATE TABLE IF NOT EXISTS pricing_reports (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    agent_id CHAR(36) NOT NULL,

    -- Instance info
    instance_id VARCHAR(50),
    instance_type VARCHAR(50),
    region VARCHAR(50),
    az VARCHAR(50),
    current_mode VARCHAR(20),
    current_pool_id VARCHAR(100),

    -- Pricing summary
    on_demand_price DECIMAL(10, 6),
    current_spot_price DECIMAL(10, 6),
    cheapest_pool_id VARCHAR(100),
    cheapest_pool_price DECIMAL(10, 6),

    -- Full data (JSON)
    spot_pools JSON,

    -- Timing
    collected_at TIMESTAMP NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_pricing_reports_agent (agent_id),
    INDEX idx_pricing_reports_time (received_at DESC),
    INDEX idx_pricing_reports_collected (collected_at DESC),

    CONSTRAINT fk_pricing_reports_agent FOREIGN KEY (agent_id)
        REFERENCES agents(id) ON DELETE CASCADE
) ENGINE=InnoDB;
```

**All tables already exist in final-ml schema!** ✅

---

### 2. Backend Code to Store Pricing Data

Update your pricing report handler to save data to these tables:

```python
@app.route('/api/agents/<agent_id>/pricing-report', methods=['POST'])
@require_client_token
def pricing_report_endpoint(agent_id):
    """
    Receive pricing report from agent (every 5 minutes)
    """
    try:
        data = request.get_json()
        instance_data = data.get('instance', {})
        pricing_data = data.get('pricing', {})

        # 1. Store pricing report (full data)
        report_id = str(uuid.uuid4())
        execute_query("""
            INSERT INTO pricing_reports (
                id, agent_id, instance_id, instance_type, region, az,
                current_mode, current_pool_id, on_demand_price, current_spot_price,
                cheapest_pool_id, cheapest_pool_price, spot_pools,
                collected_at, received_at
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
            )
        """, (
            report_id, agent_id,
            instance_data.get('instance_id'),
            instance_data.get('instance_type'),
            instance_data.get('region'),
            instance_data.get('az'),
            instance_data.get('mode'),
            instance_data.get('pool_id'),
            pricing_data.get('on_demand_price'),
            pricing_data.get('current_spot_price'),
            pricing_data.get('cheapest_pool', {}).get('pool_id'),
            pricing_data.get('cheapest_pool', {}).get('price'),
            json.dumps(pricing_data.get('spot_pools', [])),
            pricing_data.get('collected_at')
        ))

        # 2. Store spot price snapshots (for each AZ)
        spot_pools = pricing_data.get('spot_pools', [])
        for pool in spot_pools:
            pool_id = pool.get('pool_id')
            price = pool.get('price')

            if pool_id and price:
                # Ensure pool exists
                execute_query("""
                    INSERT IGNORE INTO spot_pools (id, instance_type, region, az, pool_name)
                    VALUES (%s, %s, %s, %s, %s)
                """, (
                    pool_id,
                    pool.get('instance_type'),
                    pool.get('region'),
                    pool.get('az'),
                    f"{pool.get('instance_type')} ({pool.get('az')})"
                ))

                # Store price snapshot
                execute_query("""
                    INSERT INTO spot_price_snapshots (pool_id, price, captured_at, recorded_at)
                    VALUES (%s, %s, %s, NOW())
                """, (pool_id, price, pricing_data.get('collected_at')))

        # 3. Store on-demand price snapshot
        on_demand_price = pricing_data.get('on_demand_price')
        if on_demand_price:
            execute_query("""
                INSERT INTO ondemand_price_snapshots (
                    region, instance_type, price, captured_at, recorded_at
                ) VALUES (%s, %s, %s, %s, NOW())
            """, (
                instance_data.get('region'),
                instance_data.get('instance_type'),
                on_demand_price,
                pricing_data.get('collected_at')
            ))

        logger.info(f"Stored pricing report from agent {agent_id}: {len(spot_pools)} pools")
        return jsonify({'success': True}), 200

    except Exception as e:
        logger.error(f"Error storing pricing report: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500
```

---

### 3. API Endpoint to Return Pricing History

Create the endpoint that the frontend calls:

```python
@app.route('/api/client/pricing-history', methods=['GET'])
@require_client_token
def get_pricing_history():
    """
    GET /api/client/pricing-history?days=7&agent_id=xxx

    Returns pricing history for the last N days (default 7)
    """
    try:
        client_id = request.client_id  # From @require_client_token decorator
        days = int(request.args.get('days', 7))
        agent_id = request.args.get('agent_id')  # Optional

        # Limit to 30 days max
        days = min(days, 30)

        # Build query to get pricing data points
        # We want one data point per hour for the chart
        query = """
            SELECT
                DATE_FORMAT(captured_at, '%%Y-%%m-%%d %%H:00:00') as time_bucket,
                AVG(price) as avg_price,
                pool_id
            FROM spot_price_snapshots sps
            JOIN spot_pools sp ON sp.id = sps.pool_id
            WHERE sps.captured_at >= DATE_SUB(NOW(), INTERVAL %s DAY)
        """
        params = [days]

        # Filter by agent if specified
        if agent_id:
            query += """
                AND EXISTS (
                    SELECT 1 FROM pricing_reports pr
                    WHERE pr.agent_id = %s
                      AND JSON_CONTAINS(pr.spot_pools, JSON_OBJECT('pool_id', sps.pool_id))
                      AND ABS(TIMESTAMPDIFF(MINUTE, pr.collected_at, sps.captured_at)) < 10
                )
            """
            params.append(agent_id)

        query += """
            GROUP BY time_bucket, pool_id
            ORDER BY time_bucket ASC, pool_id ASC
        """

        spot_data = execute_query(query, params, fetch=True)

        # Get on-demand pricing
        ondemand_query = """
            SELECT
                DATE_FORMAT(captured_at, '%%Y-%%m-%%d %%H:00:00') as time_bucket,
                AVG(price) as avg_price,
                instance_type,
                region
            FROM ondemand_price_snapshots
            WHERE captured_at >= DATE_SUB(NOW(), INTERVAL %s DAY)
        """
        ondemand_params = [days]

        if agent_id:
            ondemand_query += " AND EXISTS (SELECT 1 FROM agents WHERE id = %s)"
            ondemand_params.append(agent_id)

        ondemand_query += " GROUP BY time_bucket, instance_type, region ORDER BY time_bucket ASC"

        ondemand_data = execute_query(ondemand_query, ondemand_params, fetch=True)

        # Transform data into format expected by frontend
        # Group by time_bucket
        time_buckets = {}

        # Add spot prices
        for row in spot_data:
            time_bucket = row['time_bucket']
            pool_id = row['pool_id']
            price = float(row['avg_price'])

            if time_bucket not in time_buckets:
                time_buckets[time_bucket] = {
                    'timestamp': time_bucket,
                    'spot_pools': []
                }

            # Extract AZ from pool_id (e.g., "t3.medium.ap-south-1a" -> "ap-south-1a")
            az = pool_id.split('.')[-1] if '.' in pool_id else 'unknown'

            time_buckets[time_bucket]['spot_pools'].append({
                'pool_id': pool_id,
                'az': az,
                'price': price
            })

        # Add on-demand prices
        for row in ondemand_data:
            time_bucket = row['time_bucket']
            price = float(row['avg_price'])

            if time_bucket not in time_buckets:
                time_buckets[time_bucket] = {
                    'timestamp': time_bucket,
                    'spot_pools': []
                }

            time_buckets[time_bucket]['ondemand_price'] = price

        # Convert to array and sort by time
        history = sorted(time_buckets.values(), key=lambda x: x['timestamp'])

        return jsonify({
            'history': history,
            'days': days,
            'data_points': len(history)
        }), 200

    except Exception as e:
        logger.error(f"Error fetching pricing history: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500
```

---

### 4. Background Job (Optional - for Data Aggregation)

To optimize queries and storage, you can create hourly aggregated data:

```python
import schedule
import time
from threading import Thread

def aggregate_pricing_data():
    """
    Run every 12 hours to create aggregated pricing snapshots
    This makes queries faster and reduces storage
    """
    try:
        logger.info("Starting pricing data aggregation...")

        # Aggregate spot prices into hourly buckets
        execute_query("""
            INSERT INTO pricing_snapshots_clean (
                pool_id, instance_type, region, az,
                spot_price, time_bucket, bucket_start, bucket_end,
                source_type, confidence_score, data_source
            )
            SELECT
                sps.pool_id,
                sp.instance_type,
                sp.region,
                sp.az,
                AVG(sps.price) as avg_price,
                DATE_FORMAT(sps.captured_at, '%%Y-%%m-%%d %%H:00:00') as time_bucket,
                MIN(sps.captured_at) as bucket_start,
                MAX(sps.captured_at) as bucket_end,
                'measured' as source_type,
                1.00 as confidence_score,
                'measured' as data_source
            FROM spot_price_snapshots sps
            JOIN spot_pools sp ON sp.id = sps.pool_id
            WHERE sps.captured_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
            GROUP BY sps.pool_id, DATE_FORMAT(sps.captured_at, '%%Y-%%m-%%d %%H:00:00')
            ON DUPLICATE KEY UPDATE
                spot_price = VALUES(spot_price),
                bucket_start = VALUES(bucket_start),
                bucket_end = VALUES(bucket_end)
        """)

        logger.info("Pricing data aggregation completed")

    except Exception as e:
        logger.error(f"Error in pricing aggregation: {e}", exc_info=True)

# Schedule the job
def start_background_jobs():
    """Start background job scheduler"""
    schedule.every(12).hours.do(aggregate_pricing_data)

    def run_scheduler():
        while True:
            schedule.run_pending()
            time.sleep(60)  # Check every minute

    scheduler_thread = Thread(target=run_scheduler, daemon=True)
    scheduler_thread.start()
    logger.info("Background job scheduler started")

# Call this when your Flask app starts
if __name__ == '__main__':
    start_background_jobs()
    app.run(host='0.0.0.0', port=5000)
```

---

## Frontend Integration

To use the chart in your dashboard, add it to your page:

```jsx
import PricingHistoryChart from './components/PricingHistoryChart';

function DashboardPage() {
  const [agentId, setAgentId] = useState(null);

  // Get agent ID from your state/API
  useEffect(() => {
    fetch('/api/agents')
      .then(res => res.json())
      .then(data => {
        if (data.agents && data.agents.length > 0) {
          setAgentId(data.agents[0].id);
        }
      });
  }, []);

  return (
    <div className="container mx-auto p-6">
      <h1 className="text-3xl font-bold mb-6">Dashboard</h1>

      {/* Other dashboard content */}

      {/* Pricing History Chart */}
      {agentId && (
        <div className="mb-8">
          <PricingHistoryChart agentId={agentId} />
        </div>
      )}
    </div>
  );
}
```

---

## Dependencies

### Frontend
Add to `package.json`:
```json
{
  "dependencies": {
    "recharts": "^2.10.0",
    "axios": "^1.6.0"
  }
}
```

Install:
```bash
cd frontend
npm install recharts axios
```

### Backend
Add to `requirements.txt`:
```
schedule==1.2.0
```

Install:
```bash
pip install schedule
```

---

## Testing

### 1. Test Backend Endpoint

```bash
# Get pricing history for last 7 days
curl http://localhost:5000/api/client/pricing-history?days=7

# Expected response:
{
  "history": [
    {
      "timestamp": "2025-11-23 14:00:00",
      "spot_pools": [
        {"pool_id": "t3.medium.ap-south-1a", "az": "ap-south-1a", "price": 0.0132},
        {"pool_id": "t3.medium.ap-south-1b", "az": "ap-south-1b", "price": 0.0128},
        {"pool_id": "t3.medium.ap-south-1c", "az": "ap-south-1c", "price": 0.0135}
      ],
      "ondemand_price": 0.0416
    },
    ...
  ],
  "days": 7,
  "data_points": 168
}
```

### 2. Verify Data Storage

```sql
-- Check if pricing reports are being stored
SELECT COUNT(*) as report_count, MAX(received_at) as latest_report
FROM pricing_reports;

-- Check spot price snapshots
SELECT COUNT(*) as snapshot_count, MAX(captured_at) as latest_snapshot
FROM spot_price_snapshots;

-- Check on-demand snapshots
SELECT COUNT(*) as ondemand_count, MAX(captured_at) as latest_ondemand
FROM ondemand_price_snapshots;

-- View recent pricing data
SELECT
    pool_id,
    price,
    captured_at
FROM spot_price_snapshots
WHERE captured_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
ORDER BY captured_at DESC
LIMIT 20;
```

### 3. Test Frontend

1. Navigate to dashboard
2. Chart should load with 7 days of data
3. Click legend items to toggle lines
4. Hover over chart for tooltips
5. Click refresh button to manually reload

---

## Data Retention

To prevent database from growing too large:

```sql
-- Clean up old pricing data (keep 90 days)
-- Run this daily via cron or background job

DELETE FROM spot_price_snapshots
WHERE captured_at < DATE_SUB(NOW(), INTERVAL 90 DAY);

DELETE FROM ondemand_price_snapshots
WHERE captured_at < DATE_SUB(NOW(), INTERVAL 90 DAY);

DELETE FROM pricing_reports
WHERE received_at < DATE_SUB(NOW(), INTERVAL 30 DAY);
```

Add to your `cleanup_old_data()` stored procedure in the schema.

---

## Troubleshooting

### No Data Showing in Chart

1. **Check if agent is sending pricing reports:**
   ```bash
   tail -f /var/log/spot-optimizer/agent-error.log | grep "Pricing report sent"
   ```

2. **Check backend is storing data:**
   ```sql
   SELECT COUNT(*) FROM pricing_reports WHERE received_at > DATE_SUB(NOW(), INTERVAL 1 HOUR);
   ```

3. **Check API endpoint returns data:**
   ```bash
   curl http://localhost:5000/api/client/pricing-history?days=1
   ```

### Chart Shows "Loading..." Forever

- Open browser dev tools → Network tab
- Check if API request is failing
- Check browser console for errors
- Verify CORS headers are set

### Prices Look Wrong

- Check timezone handling (all times should be UTC)
- Verify aggregation query is correct
- Check if multiple agents are submitting conflicting data

---

## Summary

### What's Done ✅
- ✅ Agent already sends pricing data every 5 minutes
- ✅ Frontend chart component created
- ✅ API proxy endpoint updated

### What You Need to Do ⚠️
1. **Update backend pricing report handler** to store data in tables
2. **Create `/api/client/pricing-history` endpoint** to return 7-day data
3. **Optional: Add background job** for data aggregation every 12 hours
4. **Test** the full flow end-to-end

### Files Created
- `/frontend/src/components/PricingHistoryChart.jsx` - Chart component
- `/frontend/api_server.py` - Updated with agent_id parameter
- This documentation file

---

## Next Steps

1. Copy the backend code snippets to your final-ml backend
2. Test the pricing report storage
3. Test the pricing history endpoint
4. Deploy and monitor for 24 hours to build up data
5. View the chart in your dashboard!

Good luck! 🚀
