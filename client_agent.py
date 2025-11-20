"""
Client-Side Supportive Agent v1.0.0
===========================================================================
A lightweight agent that fetches data from the central server and executes
switches quickly (manual or model-driven).

Features:
- Fast data fetching from central server
- Quick switch execution (manual and model-driven)
- Client-specific monitoring
- Real-time status updates
- Minimal overhead
===========================================================================
"""

import os
import sys
import time
import json
import logging
import requests
import threading
from datetime import datetime
from typing import Dict, List, Optional
from dataclasses import dataclass
from urllib.parse import urljoin
from dotenv import load_dotenv

load_dotenv()

# ============================================================================
# LOGGING CONFIGURATION
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('client_agent.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ============================================================================
# CONFIGURATION
# ============================================================================

@dataclass
class ClientAgentConfig:
    """Client agent configuration"""

    # Central Server Connection
    CENTRAL_SERVER_URL: str = os.getenv('CENTRAL_SERVER_URL', 'http://localhost:5000')
    CLIENT_TOKEN: str = os.getenv('CLIENT_TOKEN', '')
    CLIENT_ID: str = os.getenv('CLIENT_ID', '')

    # Timing Configuration (Fast polling for quick response)
    STATUS_UPDATE_INTERVAL: int = int(os.getenv('STATUS_UPDATE_INTERVAL', 10))  # 10 seconds
    DATA_FETCH_INTERVAL: int = int(os.getenv('DATA_FETCH_INTERVAL', 15))  # 15 seconds
    SWITCH_CHECK_INTERVAL: int = int(os.getenv('SWITCH_CHECK_INTERVAL', 5))  # 5 seconds (very fast)

    # Agent Version
    AGENT_VERSION: str = '1.0.0'

    def validate(self) -> bool:
        """Validate required configuration"""
        if not self.CLIENT_TOKEN:
            logger.error("CLIENT_TOKEN not set!")
            return False
        if not self.CENTRAL_SERVER_URL:
            logger.error("CENTRAL_SERVER_URL not set!")
            return False
        if not self.CLIENT_ID:
            logger.error("CLIENT_ID not set!")
            return False
        return True

config = ClientAgentConfig()

# ============================================================================
# CENTRAL SERVER API CLIENT
# ============================================================================

class CentralServerAPI:
    """API client for central server communication"""

    def __init__(self):
        self.base_url = config.CENTRAL_SERVER_URL
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {config.CLIENT_TOKEN}',
            'Content-Type': 'application/json'
        })

    def _make_request(self, method: str, endpoint: str, **kwargs) -> Optional[Dict]:
        """Make HTTP request with error handling"""
        url = urljoin(self.base_url, endpoint)
        try:
            response = self.session.request(method, url, timeout=30, **kwargs)
            response.raise_for_status()
            return response.json() if response.text else {}
        except requests.exceptions.Timeout:
            logger.error(f"Request timeout: {endpoint}")
            return None
        except requests.exceptions.ConnectionError:
            logger.error(f"Connection error: {endpoint}")
            return None
        except requests.exceptions.HTTPError as e:
            logger.error(f"HTTP error {response.status_code}: {endpoint}")
            return None
        except Exception as e:
            logger.error(f"Request failed: {endpoint} - {e}")
            return None

    def get_client_info(self) -> Optional[Dict]:
        """Get client information"""
        return self._make_request('GET', f'/api/clients/{config.CLIENT_ID}')

    def get_client_agents(self) -> List[Dict]:
        """Get all agents for this client"""
        result = self._make_request('GET', f'/api/clients/{config.CLIENT_ID}/agents')
        if not result:
            return []
        return result.get('agents', result.get('data', []))

    def get_client_instances(self) -> List[Dict]:
        """Get all instances for this client"""
        result = self._make_request('GET', f'/api/clients/{config.CLIENT_ID}/instances')
        if not result:
            return []
        return result.get('instances', result.get('data', []))

    def get_client_savings(self) -> Optional[Dict]:
        """Get savings information for this client"""
        return self._make_request('GET', f'/api/clients/{config.CLIENT_ID}/savings')

    def get_pending_switches(self) -> List[Dict]:
        """Get pending switch commands for this client"""
        result = self._make_request('GET', f'/api/clients/{config.CLIENT_ID}/pending-switches')
        if not result:
            return []
        return result.get('switches', result.get('pending_switches', result.get('data', [])))

    def execute_switch(self, switch_data: Dict) -> bool:
        """Execute a switch command"""
        result = self._make_request(
            'POST',
            f'/api/clients/{config.CLIENT_ID}/execute-switch',
            json=switch_data
        )
        return result is not None

    def update_agent_status(self, status: str) -> bool:
        """Update client agent status"""
        result = self._make_request(
            'POST',
            f'/api/clients/{config.CLIENT_ID}/agent-status',
            json={
                'status': status,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'version': config.AGENT_VERSION
            }
        )
        return result is not None

# ============================================================================
# CLIENT DATA MANAGER
# ============================================================================

class ClientDataManager:
    """Manages client-specific data from central server"""

    def __init__(self, api: CentralServerAPI):
        self.api = api
        self.client_info: Optional[Dict] = None
        self.agents: List[Dict] = []
        self.instances: List[Dict] = []
        self.savings: Optional[Dict] = None
        self.last_update: Optional[datetime] = None

    def fetch_all_data(self):
        """Fetch all client data from central server"""
        logger.info("Fetching client data from central server...")

        # Fetch client info
        self.client_info = self.api.get_client_info()
        if self.client_info:
            logger.info(f"✓ Client info fetched: {self.client_info.get('name', 'Unknown')}")

        # Fetch agents
        self.agents = self.api.get_client_agents()
        logger.info(f"✓ Agents fetched: {len(self.agents)} active agents")

        # Fetch instances
        self.instances = self.api.get_client_instances()
        logger.info(f"✓ Instances fetched: {len(self.instances)} instances")

        # Fetch savings
        self.savings = self.api.get_client_savings()
        if self.savings:
            total_savings = self.savings.get('total_savings', 0)
            logger.info(f"✓ Savings fetched: ${total_savings:.2f}")

        self.last_update = datetime.utcnow()

    def get_summary(self) -> Dict:
        """Get summary of client data"""
        return {
            'client_id': config.CLIENT_ID,
            'client_name': self.client_info.get('name') if self.client_info else 'Unknown',
            'total_agents': len(self.agents),
            'total_instances': len(self.instances),
            'total_savings': self.savings.get('total_savings', 0) if self.savings else 0,
            'last_update': self.last_update.isoformat() if self.last_update else None
        }

# ============================================================================
# SWITCH EXECUTOR
# ============================================================================

class SwitchExecutor:
    """Executes switch commands quickly"""

    def __init__(self, api: CentralServerAPI):
        self.api = api

    def execute_pending_switches(self):
        """Check for and execute pending switches"""
        pending = self.api.get_pending_switches()

        if not pending:
            logger.debug("No pending switches")
            return

        logger.info(f"Found {len(pending)} pending switch(es)")

        for switch in pending:
            try:
                switch_id = switch.get('id')
                switch_type = switch.get('type', 'unknown')  # manual or model
                target_mode = switch.get('target_mode')
                agent_id = switch.get('agent_id')

                logger.info(f"Executing switch {switch_id}: type={switch_type}, target={target_mode}, agent={agent_id}")

                # Execute the switch
                success = self.api.execute_switch({
                    'switch_id': switch_id,
                    'agent_id': agent_id,
                    'target_mode': target_mode,
                    'executed_at': datetime.utcnow().isoformat() + 'Z'
                })

                if success:
                    logger.info(f"✓ Switch {switch_id} executed successfully")
                else:
                    logger.error(f"✗ Switch {switch_id} execution failed")

            except Exception as e:
                logger.error(f"Error executing switch: {e}", exc_info=True)

# ============================================================================
# MAIN CLIENT AGENT CLASS
# ============================================================================

class ClientAgent:
    """Main client agent orchestrator"""

    def __init__(self):
        self.api = CentralServerAPI()
        self.data_manager = ClientDataManager(self.api)
        self.switch_executor = SwitchExecutor(self.api)

        # Agent state
        self.is_running = False
        self.shutdown_event = threading.Event()
        self.threads: List[threading.Thread] = []

        logger.info(f"Client Agent initialized for client: {config.CLIENT_ID}")

    def start(self):
        """Start the client agent"""
        try:
            # Validate configuration
            if not config.validate():
                logger.error("Configuration validation failed!")
                return

            logger.info("="*80)
            logger.info(f"Client Agent v{config.AGENT_VERSION} Starting...")
            logger.info(f"  Client ID: {config.CLIENT_ID}")
            logger.info(f"  Central Server: {config.CENTRAL_SERVER_URL}")
            logger.info("="*80)

            self.is_running = True

            # Initial data fetch
            self.data_manager.fetch_all_data()
            summary = self.data_manager.get_summary()
            logger.info(f"Initial data summary: {json.dumps(summary, indent=2)}")

            # Send initial status update
            self.api.update_agent_status('online')

            # Start worker threads
            self._start_workers()

            logger.info("✓ Client Agent started successfully")

            # Keep main thread alive
            while self.is_running and not self.shutdown_event.is_set():
                time.sleep(1)

        except KeyboardInterrupt:
            logger.info("Received shutdown signal...")
        except Exception as e:
            logger.error(f"Agent start failed: {e}", exc_info=True)
        finally:
            self._shutdown()

    def _start_workers(self):
        """Start background worker threads"""
        workers = [
            (self._status_update_worker, "StatusUpdate"),
            (self._data_fetch_worker, "DataFetch"),
            (self._switch_check_worker, "SwitchCheck")
        ]

        for worker_func, worker_name in workers:
            thread = threading.Thread(target=worker_func, name=worker_name, daemon=True)
            thread.start()
            self.threads.append(thread)
            logger.info(f"✓ Started worker: {worker_name}")

    def _status_update_worker(self):
        """Send periodic status updates to central server"""
        logger.info("Status update worker started")

        while self.is_running and not self.shutdown_event.is_set():
            try:
                success = self.api.update_agent_status('online')
                if not success:
                    logger.warning("Status update failed")
                else:
                    logger.debug("Status update sent")

            except Exception as e:
                logger.error(f"Status update error: {e}")

            self.shutdown_event.wait(config.STATUS_UPDATE_INTERVAL)

    def _data_fetch_worker(self):
        """Periodically fetch data from central server"""
        logger.info("Data fetch worker started")

        while self.is_running and not self.shutdown_event.is_set():
            try:
                self.data_manager.fetch_all_data()
                summary = self.data_manager.get_summary()
                logger.info(f"Data updated: {summary['total_agents']} agents, {summary['total_instances']} instances, ${summary['total_savings']:.2f} savings")

            except Exception as e:
                logger.error(f"Data fetch error: {e}")

            self.shutdown_event.wait(config.DATA_FETCH_INTERVAL)

    def _switch_check_worker(self):
        """Check for and execute pending switches (very fast polling)"""
        logger.info("Switch check worker started")

        while self.is_running and not self.shutdown_event.is_set():
            try:
                self.switch_executor.execute_pending_switches()

            except Exception as e:
                logger.error(f"Switch check error: {e}")

            # Very fast polling for quick switch execution
            self.shutdown_event.wait(config.SWITCH_CHECK_INTERVAL)

    def _shutdown(self):
        """Graceful shutdown"""
        logger.info("Shutting down client agent...")

        self.is_running = False
        self.shutdown_event.set()

        # Wait for threads to finish
        for thread in self.threads:
            thread.join(timeout=5)

        # Send final offline status
        try:
            self.api.update_agent_status('offline')
        except:
            pass

        logger.info("✓ Client agent shutdown complete")

# ============================================================================
# ENTRY POINT
# ============================================================================

def main():
    """Main entry point"""
    agent = ClientAgent()
    agent.start()

if __name__ == '__main__':
    main()
