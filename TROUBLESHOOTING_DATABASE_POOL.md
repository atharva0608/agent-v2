# Troubleshooting: Database Connection Pool Exhaustion

## Problem

The spot optimizer agent is unable to register with the central server and instances are not appearing in the dashboard. All API requests from the agent are failing with **HTTP 500 errors** and the message:

```
{"error":"Failed getting connection; pool exhausted"}
```

## Root Cause

The **central server backend (final-ml repo)** has a database connection pool exhaustion issue. This means:

1. The database connection pool has run out of available connections
2. All incoming requests are being rejected because there are no free database connections
3. The agent cannot register, send heartbeats, or communicate with the server

## Where the Problem Is

- **NOT** in the agent code (this repo: agent-v2)
- **YES** in the central server backend (repo: final-ml)

## How to Fix (in final-ml repo)

### Option 1: Fix Database Connection Pool Configuration

Add or update the following environment variables in your central server's configuration:

```bash
# Database connection pool settings
SQLALCHEMY_POOL_SIZE=20          # Default pool size (increase from default 5)
SQLALCHEMY_MAX_OVERFLOW=40       # Maximum overflow connections
SQLALCHEMY_POOL_RECYCLE=3600     # Recycle connections after 1 hour (prevent stale connections)
SQLALCHEMY_POOL_PRE_PING=true    # Test connections before using them
SQLALCHEMY_POOL_TIMEOUT=30       # Timeout waiting for a connection
```

### Option 2: Check for Connection Leaks

In your Flask/SQLAlchemy application (final-ml), ensure database sessions are properly closed:

```python
# Bad - connection leak
def my_endpoint():
    session = db.session()
    data = session.query(Model).all()
    return data  # Session never closed!

# Good - properly closed
def my_endpoint():
    try:
        session = db.session()
        data = session.query(Model).all()
        return data
    finally:
        session.close()  # Always close

# Better - use context manager
def my_endpoint():
    with db.session() as session:
        data = session.query(Model).all()
        return data  # Automatically closed
```

### Option 3: Restart the Backend Server

Sometimes connections get stuck. Restart your central server:

```bash
# On the central server
sudo systemctl restart spot-optimizer-backend
# or
sudo systemctl restart gunicorn
# or if running manually
pkill -f gunicorn && python app.py
```

## Checking the Fix

After applying the fix in the final-ml repo:

1. Restart the central server backend
2. Monitor the agent logs using:
   ```bash
   spot-optimizer-logs
   ```
3. Look for successful registration:
   ```
   Agent started - ID: <agent-id>
   Pricing report sent: 3 pools
   ```
4. Check the dashboard - the instance should now appear

## Detailed Error Log Example

When the pool is exhausted, you'll see logs like this:

```
2025-11-23 15:34:34,720 - main - ERROR - HTTP error 500: /api/agents/.../heartbeat - <!doctype html>
<html lang=en> <title>500 Internal Server Error</title>

2025-11-23 15:34:35,983 - main - ERROR - HTTP error 500: /api/agents/.../pricing-report -
{"error":"Failed getting connection; pool exhausted"}
```

With the enhanced logging (after this commit), you'll see:

```
================================================================================
DATABASE CONNECTION POOL EXHAUSTED ON CENTRAL SERVER!
Endpoint: /api/agents/.../heartbeat
This is a BACKEND ISSUE in the central server (final-ml repo)
Action Required: Fix database connection pool configuration
  1. Check database connection pool size (SQLALCHEMY_POOL_SIZE)
  2. Check max overflow (SQLALCHEMY_MAX_OVERFLOW)
  3. Check pool recycle time (SQLALCHEMY_POOL_RECYCLE)
  4. Ensure database connections are properly closed
================================================================================
```

## Prevention

To prevent this in the future:

1. **Monitor database connections** - Set up monitoring for pool usage
2. **Use connection pooling best practices** - Always close sessions
3. **Set appropriate pool sizes** - Based on expected concurrent requests
4. **Enable pool recycling** - Prevent stale connections from accumulating
5. **Use health checks** - Implement `/health` endpoint to detect pool issues early

## Reference

- SQLAlchemy Pool Configuration: https://docs.sqlalchemy.org/en/14/core/pooling.html
- Flask-SQLAlchemy Configuration: https://flask-sqlalchemy.palletsprojects.com/en/2.x/config/
