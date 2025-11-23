-- ============================================================================
-- AWS Spot Optimizer - Required Database Schema for Full Agent Functionality
-- ============================================================================
-- This schema contains tables that may be missing from the central server
-- for full agent v4.0.0 functionality
-- ============================================================================

-- ============================================================================
-- CLEANUP TRACKING
-- ============================================================================

CREATE TABLE IF NOT EXISTS cleanup_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    agent_id VARCHAR(36),
    client_id VARCHAR(36),
    cleanup_type ENUM('snapshots', 'amis', 'full') NOT NULL,
    deleted_snapshots_count INT DEFAULT 0,
    deleted_amis_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    details JSON,
    cutoff_date TIMESTAMP NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_agent_id (agent_id),
    INDEX idx_client_id (client_id),
    INDEX idx_executed_at (executed_at)
);

-- ============================================================================
-- TERMINATION & REBALANCE EVENTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS termination_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    agent_id VARCHAR(36) NOT NULL,
    instance_id VARCHAR(50) NOT NULL,
    event_type ENUM('termination_notice', 'rebalance_recommendation') NOT NULL,
    action_type VARCHAR(50),
    action_taken VARCHAR(255),
    emergency_replica_id VARCHAR(36),
    new_instance_id VARCHAR(50),
    detected_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP NULL,
    status ENUM('detected', 'handling', 'resolved', 'failed') DEFAULT 'detected',
    error_message TEXT,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_agent_id (agent_id),
    INDEX idx_instance_id (instance_id),
    INDEX idx_event_type (event_type),
    INDEX idx_status (status),
    INDEX idx_detected_at (detected_at)
);

-- ============================================================================
-- SAVINGS TRACKING
-- ============================================================================

CREATE TABLE IF NOT EXISTS savings_snapshots (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_id VARCHAR(36) NOT NULL,
    snapshot_date DATE NOT NULL,
    total_savings DECIMAL(15, 4) DEFAULT 0,
    daily_savings DECIMAL(15, 4) DEFAULT 0,
    spot_hours DECIMAL(10, 2) DEFAULT 0,
    ondemand_hours DECIMAL(10, 2) DEFAULT 0,
    total_cost DECIMAL(15, 4) DEFAULT 0,
    would_be_cost DECIMAL(15, 4) DEFAULT 0,
    average_savings_percent DECIMAL(5, 2) DEFAULT 0,
    switch_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_client_date (client_id, snapshot_date),
    INDEX idx_snapshot_date (snapshot_date)
);

-- ============================================================================
-- AGENT HEALTH METRICS
-- ============================================================================

CREATE TABLE IF NOT EXISTS agent_health_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    agent_id VARCHAR(36) NOT NULL,
    metric_time TIMESTAMP NOT NULL,
    heartbeat_latency_ms INT,
    command_execution_time_ms INT,
    pricing_fetch_success BOOLEAN,
    termination_check_success BOOLEAN,
    rebalance_check_success BOOLEAN,
    error_count INT DEFAULT 0,
    warning_count INT DEFAULT 0,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_agent_id (agent_id),
    INDEX idx_metric_time (metric_time)
);

-- ============================================================================
-- REPLICA COST TRACKING
-- ============================================================================

CREATE TABLE IF NOT EXISTS replica_cost_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    replica_id VARCHAR(36) NOT NULL,
    agent_id VARCHAR(36) NOT NULL,
    client_id VARCHAR(36) NOT NULL,
    instance_id VARCHAR(50),
    pool_id VARCHAR(100),
    hourly_cost DECIMAL(10, 6),
    log_time TIMESTAMP NOT NULL,
    duration_hours DECIMAL(5, 2) DEFAULT 1,
    total_cost DECIMAL(10, 4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_replica_id (replica_id),
    INDEX idx_agent_id (agent_id),
    INDEX idx_client_id (client_id),
    INDEX idx_log_time (log_time)
);

-- ============================================================================
-- SPOT POOL RISK SCORES
-- ============================================================================

CREATE TABLE IF NOT EXISTS pool_risk_analysis (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pool_id VARCHAR(100) NOT NULL,
    instance_type VARCHAR(50) NOT NULL,
    region VARCHAR(20) NOT NULL,
    az VARCHAR(30) NOT NULL,
    analysis_time TIMESTAMP NOT NULL,
    risk_score DECIMAL(5, 4) DEFAULT 0,
    price_volatility DECIMAL(10, 6),
    avg_price_24h DECIMAL(10, 6),
    min_price_24h DECIMAL(10, 6),
    max_price_24h DECIMAL(10, 6),
    interruption_frequency INT DEFAULT 0,
    recommendation ENUM('safe', 'caution', 'avoid') DEFAULT 'safe',
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_pool_id (pool_id),
    INDEX idx_analysis_time (analysis_time),
    INDEX idx_risk_score (risk_score),
    INDEX idx_recommendation (recommendation)
);

-- ============================================================================
-- ALTER EXISTING TABLES (if they exist)
-- ============================================================================

-- Add columns to agents table for termination tracking
-- Run these only if the columns don't exist

-- ALTER TABLE agents ADD COLUMN IF NOT EXISTS last_termination_notice_at TIMESTAMP NULL;
-- ALTER TABLE agents ADD COLUMN IF NOT EXISTS last_rebalance_recommendation_at TIMESTAMP NULL;
-- ALTER TABLE agents ADD COLUMN IF NOT EXISTS emergency_replica_count INT DEFAULT 0;
-- ALTER TABLE agents ADD COLUMN IF NOT EXISTS cleanup_enabled BOOLEAN DEFAULT true;
-- ALTER TABLE agents ADD COLUMN IF NOT EXISTS last_cleanup_at TIMESTAMP NULL;

-- Add columns to replica_instances table
-- ALTER TABLE replica_instances ADD COLUMN IF NOT EXISTS total_runtime_hours DECIMAL(10, 2) DEFAULT 0;
-- ALTER TABLE replica_instances ADD COLUMN IF NOT EXISTS accumulated_cost DECIMAL(15, 4) DEFAULT 0;

-- ============================================================================
-- VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW v_client_savings_summary AS
SELECT
    c.id AS client_id,
    c.name AS client_name,
    COALESCE(SUM(ss.total_savings), 0) AS lifetime_savings,
    COALESCE(SUM(CASE
        WHEN ss.snapshot_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        THEN ss.daily_savings ELSE 0 END), 0) AS monthly_savings,
    COALESCE(SUM(CASE
        WHEN ss.snapshot_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
        THEN ss.daily_savings ELSE 0 END), 0) AS weekly_savings,
    COALESCE(AVG(ss.average_savings_percent), 0) AS avg_savings_percent,
    COUNT(DISTINCT a.id) AS agent_count,
    SUM(CASE WHEN a.status = 'online' THEN 1 ELSE 0 END) AS online_agents
FROM clients c
LEFT JOIN savings_snapshots ss ON c.id = ss.client_id
LEFT JOIN agents a ON c.id = a.client_id
GROUP BY c.id, c.name;

CREATE OR REPLACE VIEW v_recent_termination_events AS
SELECT
    te.*,
    a.hostname,
    a.instance_type,
    c.name AS client_name
FROM termination_events te
JOIN agents a ON te.agent_id = a.id
JOIN clients c ON a.client_id = c.id
WHERE te.detected_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
ORDER BY te.detected_at DESC;

CREATE OR REPLACE VIEW v_pool_risk_current AS
SELECT
    pool_id,
    instance_type,
    region,
    az,
    risk_score,
    price_volatility,
    avg_price_24h,
    recommendation,
    analysis_time
FROM pool_risk_analysis pra
WHERE analysis_time = (
    SELECT MAX(analysis_time)
    FROM pool_risk_analysis
    WHERE pool_id = pra.pool_id
);

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

DELIMITER //

CREATE PROCEDURE IF NOT EXISTS sp_calculate_daily_savings(IN p_date DATE)
BEGIN
    INSERT INTO savings_snapshots (client_id, snapshot_date, daily_savings, switch_count)
    SELECT
        c.id,
        p_date,
        COALESCE(SUM(s.savings_impact * 24), 0) AS daily_savings,
        COUNT(s.id) AS switch_count
    FROM clients c
    LEFT JOIN switches s ON c.id = s.client_id
        AND DATE(s.initiated_at) = p_date
    GROUP BY c.id
    ON DUPLICATE KEY UPDATE
        daily_savings = VALUES(daily_savings),
        switch_count = VALUES(switch_count),
        updated_at = NOW();
END //

CREATE PROCEDURE IF NOT EXISTS sp_cleanup_old_metrics(IN days_to_keep INT)
BEGIN
    DELETE FROM agent_health_metrics
    WHERE metric_time < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);

    DELETE FROM pool_risk_analysis
    WHERE analysis_time < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);

    DELETE FROM replica_cost_log
    WHERE log_time < DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
END //

DELIMITER ;

-- ============================================================================
-- SCHEDULED EVENTS (MySQL)
-- ============================================================================

-- Calculate daily savings at midnight
CREATE EVENT IF NOT EXISTS evt_calculate_daily_savings
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY)
DO CALL sp_calculate_daily_savings(DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY));

-- Cleanup old metrics weekly
CREATE EVENT IF NOT EXISTS evt_cleanup_old_metrics
ON SCHEDULE EVERY 1 WEEK
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 WEEK)
DO CALL sp_cleanup_old_metrics(30);
