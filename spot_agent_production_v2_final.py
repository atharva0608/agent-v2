"""
AWS Spot Optimizer - Production Agent v2.0.0 (FINAL - FULLY COMPATIBLE)
==========================================================================
✓ 100% compatible with existing backend schema
✓ Full switching functionality with AMI snapshots
✓ Automatic instance termination
✓ Real-time instance type detection
✓ Complete error handling
✓ Proper backend integration
"""

import os
import sys
import json
import time
import logging
import boto3
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from threading import Thread, Event, Lock
import requests
from dotenv import load_dotenv

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/spot-optimizer/agent.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class AgentConfig:
    central_server_url: str = os.getenv('CENTRAL_SERVER_URL', '')
    client_token: str = os.getenv('CLIENT_TOKEN', '')
    region: str = os.getenv('AWS_REGION', 'ap-south-1')
    instance_id: str = ''
    instance_type: str = ''
    availability_zone: str = ''
    ami_id: str = ''
    agent_id: str = ''
    hostname: str = ''
    agent_version: str = '2.0.0'
    spot_price_interval: int = 600
    ondemand_price_interval: int = 3600
    heartbeat_interval: int = 60
    command_check_interval: int = 30
    enabled: bool = True
    auto_switch_enabled: bool = True
    auto_terminate_enabled: bool = True
    is_ec2: bool = True

class AWSMetadataClient:
    """Enhanced metadata client with IMDSv2 support"""
    METADATA_BASE = "http://169.254.169.254/latest/meta-data"
    TOKEN_URL = "http://169.254.169.254/latest/api/token"
    TOKEN_TTL = "21600"
    
    def __init__(self):
        self.token = None
        self.token_expiry = None
    
    def _get_token(self) -> Optional[str]:
        """Get IMDSv2 token"""
        if self.token and self.token_expiry and datetime.now() < self.token_expiry:
            return self.token
        
        try:
            response = requests.put(
                self.TOKEN_URL,
                headers={"X-aws-ec2-metadata-token-ttl-seconds": self.TOKEN_TTL},
                timeout=2
            )
            if response.status_code == 200:
                self.token = response.text
                self.token_expiry = datetime.now() + timedelta(seconds=int(self.TOKEN_TTL))
                return self.token
        except Exception as e:
            logger.debug(f"Failed to get IMDSv2 token: {e}")
        
        return None
    
    def _fetch_metadata(self, path: str) -> Optional[str]:
        """Fetch metadata with IMDSv2 token"""
        url = f"{self.METADATA_BASE}/{path}"
        headers = {}
        
        token = self._get_token()
        if token:
            headers["X-aws-ec2-metadata-token"] = token
        
        try:
            response = requests.get(url, headers=headers, timeout=2)
            if response.status_code == 200:
                return response.text.strip()
        except Exception as e:
            logger.debug(f"Failed to fetch metadata {path}: {e}")
        
        return None
    
    def get_instance_id(self) -> Optional[str]:
        return self._fetch_metadata("instance-id")
    
    def get_instance_type(self) -> Optional[str]:
        return self._fetch_metadata("instance-type")
    
    def get_availability_zone(self) -> Optional[str]:
        return self._fetch_metadata("placement/availability-zone")
    
    def get_ami_id(self) -> Optional[str]:
        return self._fetch_metadata("ami-id")
    
    def get_hostname(self) -> Optional[str]:
        hostname = self._fetch_metadata("hostname")
        if hostname:
            return hostname
        import socket
        return socket.gethostname()
    
    def check_ec2_environment(self) -> bool:
        """Check if running on EC2"""
        # Try to get instance ID - if we can, we're on EC2
        instance_id = self.get_instance_id()
        if instance_id and instance_id.startswith('i-'):
            return True
        return False

class AWSResourceManager:
    """Manages AWS resources for instance switching"""
    
    def __init__(self, region: str):
        self.region = region
        self.ec2 = boto3.client('ec2', region_name=region)
        self.ec2_resource = boto3.resource('ec2', region_name=region)
        self.pricing = boto3.client('pricing', region_name='us-east-1')
    
    def get_instance_details(self, instance_id: str) -> Optional[Dict]:
        """Get complete instance details"""
        try:
            response = self.ec2.describe_instances(InstanceIds=[instance_id])
            if response['Reservations']:
                instance = response['Reservations'][0]['Instances'][0]
                return {
                    'instance_id': instance['InstanceId'],
                    'instance_type': instance['InstanceType'],
                    'state': instance['State']['Name'],
                    'lifecycle': instance.get('InstanceLifecycle', 'normal'),
                    'az': instance['Placement']['AvailabilityZone'],
                    'subnet_id': instance.get('SubnetId'),
                    'security_groups': [sg['GroupId'] for sg in instance.get('SecurityGroups', [])],
                    'key_name': instance.get('KeyName'),
                    'iam_instance_profile': instance.get('IamInstanceProfile', {}).get('Arn'),
                    'tags': {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])},
                    'network_interfaces': instance.get('NetworkInterfaces', []),
                    'block_device_mappings': instance.get('BlockDeviceMappings', [])
                }
        except Exception as e:
            logger.error(f"Failed to get instance details: {e}")
            return None
    
    def get_current_mode(self, instance_id: str) -> Tuple[str, Optional[str]]:
        """Get current instance mode and pool"""
        try:
            details = self.get_instance_details(instance_id)
            if not details:
                return ('unknown', None)
            
            lifecycle = details['lifecycle']
            if lifecycle == 'spot':
                pool_id = f"{details['instance_type']}_{details['az'].replace('-', '')}"
                return ('spot', pool_id)
            else:
                return ('ondemand', None)
        except Exception as e:
            logger.error(f"Failed to get instance mode: {e}")
            return ('unknown', None)
    
    def create_ami_from_instance(self, instance_id: str, name_prefix: str) -> Optional[str]:
        """Create AMI from instance"""
        try:
            timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
            ami_name = f"{name_prefix}-{timestamp}"
            
            logger.info(f"Creating AMI: {ami_name}")
            
            response = self.ec2.create_image(
                InstanceId=instance_id,
                Name=ami_name,
                Description=f"Automated snapshot for spot optimization - {timestamp}",
                NoReboot=True
            )
            
            ami_id = response['ImageId']
            logger.info(f"✓ AMI created: {ami_id}")
            
            # Wait for AMI to be available
            waiter = self.ec2.get_waiter('image_available')
            logger.info(f"Waiting for AMI {ami_id} to be available...")
            waiter.wait(
                ImageIds=[ami_id],
                WaiterConfig={'Delay': 15, 'MaxAttempts': 40}
            )
            
            logger.info(f"✓ AMI {ami_id} is available")
            return ami_id
            
        except Exception as e:
            logger.error(f"Failed to create AMI: {e}")
            return None
    
    def launch_instance(self, config: Dict, target_mode: str, target_pool_id: Optional[str] = None) -> Optional[str]:
        """Launch new instance (spot or on-demand)"""
        try:
            launch_params = {
                'ImageId': config['ami_id'],
                'InstanceType': config['instance_type'],
                'MinCount': 1,
                'MaxCount': 1,
                'TagSpecifications': [{
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': k, 'Value': v} for k, v in config.get('tags', {}).items()
                    ] + [
                        {'Key': 'spot-optimizer-managed', 'Value': 'true'},
                        {'Key': 'spot-optimizer-parent', 'Value': config['old_instance_id']},
                        {'Key': 'spot-optimizer-created', 'Value': datetime.utcnow().isoformat()}
                    ]
                }]
            }
            
            # Add optional parameters
            if config.get('key_name'):
                launch_params['KeyName'] = config['key_name']
            
            if config.get('iam_instance_profile'):
                launch_params['IamInstanceProfile'] = {
                    'Arn': config['iam_instance_profile']
                }
            
            # Network configuration
            if config.get('network_interfaces') and config['network_interfaces']:
                ni = config['network_interfaces'][0]
                launch_params['NetworkInterfaces'] = [{
                    'DeviceIndex': 0,
                    'SubnetId': config['subnet_id'],
                    'Groups': config['security_groups'],
                    'AssociatePublicIpAddress': ni.get('Association', {}).get('PublicIp') is not None
                }]
            else:
                launch_params['SecurityGroupIds'] = config['security_groups']
                launch_params['SubnetId'] = config['subnet_id']
            
            # Configure for spot or on-demand
            if target_mode == 'spot':
                launch_params['InstanceMarketOptions'] = {
                    'MarketType': 'spot',
                    'SpotOptions': {
                        'SpotInstanceType': 'persistent',
                        'InstanceInterruptionBehavior': 'stop'
                    }
                }
                logger.info(f"Launching SPOT instance in {target_pool_id}")
            else:
                logger.info(f"Launching ON-DEMAND instance")
            
            response = self.ec2.run_instances(**launch_params)
            new_instance_id = response['Instances'][0]['InstanceId']
            
            logger.info(f"✓ Launched instance: {new_instance_id}")
            
            # Wait for instance to be running
            waiter = self.ec2.get_waiter('instance_running')
            logger.info(f"Waiting for instance {new_instance_id} to be running...")
            waiter.wait(InstanceIds=[new_instance_id])
            
            logger.info(f"✓ Instance {new_instance_id} is running")
            return new_instance_id
            
        except Exception as e:
            logger.error(f"Failed to launch instance: {e}")
            return None
    
    def terminate_instance(self, instance_id: str) -> bool:
        """Terminate instance"""
        try:
            logger.info(f"Terminating instance: {instance_id}")
            self.ec2.terminate_instances(InstanceIds=[instance_id])
            logger.info(f"✓ Instance {instance_id} termination initiated")
            return True
        except Exception as e:
            logger.error(f"Failed to terminate instance: {e}")
            return False
    
    def get_spot_prices(self, instance_type: str) -> List[Dict]:
        """Get current spot prices for all AZs"""
        try:
            response = self.ec2.describe_spot_price_history(
                InstanceTypes=[instance_type],
                ProductDescriptions=['Linux/UNIX'],
                MaxResults=100,
                StartTime=datetime.utcnow() - timedelta(minutes=5)
            )
            
            pools = []
            seen_azs = set()
            
            for item in response['SpotPriceHistory']:
                az = item['AvailabilityZone']
                if az not in seen_azs:
                    pool_id = f"{instance_type}_{az.replace('-', '')}"
                    pools.append({
                        'az': az,
                        'pool_id': pool_id,
                        'price': float(item['SpotPrice'])
                    })
                    seen_azs.add(az)
            
            return pools
        except Exception as e:
            logger.error(f"Failed to get spot prices: {e}")
            return []
    
    def get_ondemand_price(self, instance_type: str) -> Optional[float]:
        """Get on-demand price"""
        try:
            region_map = {
                'us-east-1': 'US East (N. Virginia)',
                'us-west-2': 'US West (Oregon)',
                'ap-south-1': 'Asia Pacific (Mumbai)',
                'eu-west-1': 'EU (Ireland)',
                'us-east-2': 'US East (Ohio)',
                'ap-southeast-1': 'Asia Pacific (Singapore)',
            }
            
            location = region_map.get(self.region, self.region)
            
            response = self.pricing.get_products(
                ServiceCode='AmazonEC2',
                Filters=[
                    {'Type': 'TERM_MATCH', 'Field': 'instanceType', 'Value': instance_type},
                    {'Type': 'TERM_MATCH', 'Field': 'location', 'Value': location},
                    {'Type': 'TERM_MATCH', 'Field': 'operatingSystem', 'Value': 'Linux'},
                    {'Type': 'TERM_MATCH', 'Field': 'tenancy', 'Value': 'Shared'},
                    {'Type': 'TERM_MATCH', 'Field': 'preInstalledSw', 'Value': 'NA'},
                    {'Type': 'TERM_MATCH', 'Field': 'capacitystatus', 'Value': 'Used'}
                ],
                MaxResults=1
            )
            
            if response['PriceList']:
                price_item = json.loads(response['PriceList'][0])
                on_demand = price_item['terms']['OnDemand']
                price_dimensions = list(on_demand.values())[0]['priceDimensions']
                price = list(price_dimensions.values())[0]['pricePerUnit']['USD']
                return float(price)
            
            return None
        except Exception as e:
            logger.error(f"Failed to get on-demand price: {e}")
            return None

class CentralServerClient:
    """Client for communicating with central server"""
    
    def __init__(self, config: AgentConfig):
        self.config = config
        self.base_url = config.central_server_url
        self.headers = {
            'Authorization': f'Bearer {config.client_token}',
            'Content-Type': 'application/json'
        }
    
    def register_agent(self) -> Dict:
        """Register agent with server"""
        try:
            data = {
                'client_token': self.config.client_token,
                'hostname': self.config.hostname,
                'instance_id': self.config.instance_id,
                'instance_type': self.config.instance_type,
                'region': self.config.region,
                'az': self.config.availability_zone,
                'ami_id': self.config.ami_id,
                'agent_version': self.config.agent_version
            }
            
            logger.info(f"Registering agent with server...")
            
            response = requests.post(
                f"{self.base_url}/api/agents/register",
                json=data,
                headers=self.headers,
                timeout=30
            )
            
            response.raise_for_status()
            result = response.json()
            
            config_data = result.get('config', {})
            self.config.agent_id = result['agent_id']
            self.config.enabled = config_data.get('enabled', True)
            self.config.auto_switch_enabled = config_data.get('auto_switch_enabled', True)
            self.config.auto_terminate_enabled = config_data.get('auto_terminate_enabled', True)
            
            logger.info(f"✓ Agent registered: {self.config.agent_id}")
            return result
            
        except Exception as e:
            logger.error(f"Failed to register agent: {e}")
            raise
    
    def send_heartbeat(self, status: str = 'online', monitored_instances: List[str] = None) -> bool:
        """Send heartbeat to server"""
        try:
            data = {
                'status': status,
                'monitored_instances': monitored_instances or []
            }
            
            response = requests.post(
                f"{self.base_url}/api/agents/{self.config.agent_id}/heartbeat",
                json=data,
                headers=self.headers,
                timeout=10
            )
            response.raise_for_status()
            return True
        except Exception as e:
            logger.debug(f"Heartbeat failed: {e}")
            return False
    
    def send_pricing_report(self, instance_data: Dict, on_demand_price: Dict, spot_pools: List[Dict]) -> bool:
        """Send pricing data to server"""
        try:
            data = {
                'instance': instance_data,
                'on_demand_price': on_demand_price,
                'spot_pools': spot_pools
            }
            
            response = requests.post(
                f"{self.base_url}/api/agents/{self.config.agent_id}/pricing-report",
                json=data,
                headers=self.headers,
                timeout=30
            )
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Pricing report failed: {e}")
            return False
    
    def get_config(self) -> Optional[Dict]:
        """Get agent configuration from server"""
        try:
            response = requests.get(
                f"{self.base_url}/api/agents/{self.config.agent_id}/config",
                headers=self.headers,
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.debug(f"Failed to get config: {e}")
            return None
    
    def get_pending_commands(self) -> List[Dict]:
        """Get pending switch commands"""
        try:
            response = requests.get(
                f"{self.base_url}/api/agents/{self.config.agent_id}/pending-commands",
                headers=self.headers,
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.debug(f"Failed to get pending commands: {e}")
            return []
    
    def mark_command_executed(self, command_id: int) -> bool:
        """Mark command as executed"""
        try:
            response = requests.post(
                f"{self.base_url}/api/agents/{self.config.agent_id}/mark-command-executed",
                json={'command_id': command_id},
                headers=self.headers,
                timeout=10
            )
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to mark command executed: {e}")
            return False
    
    def report_switch_event(self, old_instance: Dict, new_instance: Dict, 
                           snapshot: Dict, prices: Dict, timing: Dict, trigger: str) -> bool:
        """Report successful switch to server - COMPATIBLE WITH BACKEND"""
        try:
            data = {
                'old_instance': old_instance,
                'new_instance': new_instance,
                'snapshot': snapshot,
                'prices': prices,
                'timing': timing,
                'trigger': trigger
            }
            
            response = requests.post(
                f"{self.base_url}/api/agents/{self.config.agent_id}/switch-report",
                json=data,
                headers=self.headers,
                timeout=30
            )
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to report switch event: {e}")
            return False

class SpotOptimizerAgent:
    """Main agent orchestrator"""
    
    def __init__(self, config: AgentConfig):
        self.config = config
        self.metadata_client = AWSMetadataClient()
        self.resource_manager = None
        self.server_client = CentralServerClient(config)
        self.stop_event = Event()
        self.switch_lock = Lock()
        self.threads = []
        self.last_ondemand_price = None
        self.last_ondemand_fetch = None
        self.current_mode = None
        self.current_pool_id = None
        self.switching_in_progress = False
    
    def initialize(self):
        """Initialize agent"""
        logger.info("="*80)
        logger.info("AWS Spot Optimizer Agent v2.0.0 Starting...")
        logger.info("="*80)
        
        # Check EC2 environment
        logger.info("Checking EC2 environment...")
        self.config.is_ec2 = self.metadata_client.check_ec2_environment()
        
        if not self.config.is_ec2:
            logger.error("NOT running on EC2 - Agent requires EC2 environment")
            sys.exit(1)
        
        logger.info("✓ Running on EC2 instance")
        
        # Fetch metadata
        logger.info("Fetching instance metadata...")
        self.config.instance_id = self.metadata_client.get_instance_id()
        self.config.instance_type = self.metadata_client.get_instance_type()
        self.config.availability_zone = self.metadata_client.get_availability_zone()
        self.config.ami_id = self.metadata_client.get_ami_id()
        self.config.hostname = self.metadata_client.get_hostname()
        
        if not all([self.config.instance_id, self.config.instance_type, 
                   self.config.availability_zone, self.config.ami_id]):
            logger.error("Failed to fetch instance metadata")
            sys.exit(1)
        
        logger.info(f"Instance ID: {self.config.instance_id}")
        logger.info(f"Instance Type: {self.config.instance_type}")
        logger.info(f"Availability Zone: {self.config.availability_zone}")
        logger.info(f"AMI ID: {self.config.ami_id}")
        logger.info(f"Hostname: {self.config.hostname}")
        
        # Initialize AWS resource manager
        try:
            self.resource_manager = AWSResourceManager(self.config.region)
            self.current_mode, self.current_pool_id = self.resource_manager.get_current_mode(
                self.config.instance_id
            )
            logger.info(f"Current Mode: {self.current_mode}")
            if self.current_pool_id:
                logger.info(f"Current Pool: {self.current_pool_id}")
        except Exception as e:
            logger.error(f"Failed to initialize resource manager: {e}")
            sys.exit(1)
        
        # Register with server
        logger.info("Registering with central server...")
        try:
            self.server_client.register_agent()
        except Exception as e:
            logger.error(f"Failed to register with server: {e}")
            sys.exit(1)
        
        logger.info("="*80)
        logger.info("✓ Agent initialized successfully")
        logger.info(f"  - Agent ID: {self.config.agent_id}")
        logger.info(f"  - Enabled: {self.config.enabled}")
        logger.info(f"  - Auto Switch: {self.config.auto_switch_enabled}")
        logger.info(f"  - Auto Terminate: {self.config.auto_terminate_enabled}")
        logger.info("="*80)
    
    def start_monitoring_threads(self):
        """Start all monitoring threads"""
        threads_config = [
            ('Heartbeat', self._heartbeat_loop),
            ('Spot Price Monitor', self._spot_price_monitor),
            ('On-Demand Price Monitor', self._ondemand_price_monitor),
            ('Command Processor', self._command_processor_loop),
        ]
        
        for name, target in threads_config:
            thread = Thread(target=target, name=name, daemon=True)
            thread.start()
            self.threads.append(thread)
            logger.info(f"✓ Started {name} thread")
    
    def _heartbeat_loop(self):
        """Heartbeat thread"""
        while not self.stop_event.is_set():
            try:
                success = self.server_client.send_heartbeat(
                    status='online',
                    monitored_instances=[self.config.instance_id]
                )
                
                if success:
                    config = self.server_client.get_config()
                    if config:
                        self.config.enabled = config.get('enabled', self.config.enabled)
                        self.config.auto_switch_enabled = config.get('auto_switch_enabled', self.config.auto_switch_enabled)
                        self.config.auto_terminate_enabled = config.get('auto_terminate_enabled', self.config.auto_terminate_enabled)
                
            except Exception as e:
                logger.debug(f"Heartbeat error: {e}")
            
            self.stop_event.wait(self.config.heartbeat_interval)
    
    def _spot_price_monitor(self):
        """Spot price monitoring thread"""
        while not self.stop_event.is_set():
            try:
                # Update instance type from metadata (in case it changed)
                current_type = self.metadata_client.get_instance_type()
                if current_type and current_type != self.config.instance_type:
                    logger.info(f"Instance type changed: {self.config.instance_type} -> {current_type}")
                    self.config.instance_type = current_type
                
                spot_pools = self.resource_manager.get_spot_prices(self.config.instance_type)
                
                if spot_pools:
                    on_demand_price = self._get_ondemand_price()
                    
                    # Update current mode
                    self.current_mode, self.current_pool_id = self.resource_manager.get_current_mode(
                        self.config.instance_id
                    )
                    
                    instance_data = {
                        'instance_id': self.config.instance_id,
                        'instance_type': self.config.instance_type,
                        'region': self.config.region,
                        'az': self.config.availability_zone,
                        'ami_id': self.config.ami_id,
                        'current_mode': self.current_mode,
                        'current_pool_id': self.current_pool_id
                    }
                    
                    on_demand_data = {
                        'price': on_demand_price,
                        'source': 'api'
                    }
                    
                    success = self.server_client.send_pricing_report(
                        instance_data, on_demand_data, spot_pools
                    )
                    
                    if success:
                        logger.info(f"✓ Sent pricing report: {len(spot_pools)} pools")
                
            except Exception as e:
                logger.error(f"Spot price monitor error: {e}")
            
            self.stop_event.wait(self.config.spot_price_interval)
    
    def _ondemand_price_monitor(self):
        """On-demand price monitoring thread"""
        while not self.stop_event.is_set():
            try:
                price = self.resource_manager.get_ondemand_price(self.config.instance_type)
                
                if price:
                    self.last_ondemand_price = price
                    self.last_ondemand_fetch = datetime.utcnow()
                    logger.info(f"✓ Fetched on-demand price: ${price:.6f}")
                
            except Exception as e:
                logger.error(f"On-demand price monitor error: {e}")
            
            self.stop_event.wait(self.config.ondemand_price_interval)
    
    def _command_processor_loop(self):
        """Command processing thread"""
        while not self.stop_event.is_set():
            try:
                if not self.config.enabled or not self.config.auto_switch_enabled:
                    self.stop_event.wait(self.config.command_check_interval)
                    continue
                
                if self.switching_in_progress:
                    logger.debug("Switch already in progress, skipping command check")
                    self.stop_event.wait(self.config.command_check_interval)
                    continue
                
                commands = self.server_client.get_pending_commands()
                
                if commands:
                    logger.info(f"✓ Received {len(commands)} pending command(s)")
                    
                    for cmd in commands:
                        if cmd['instance_id'] == self.config.instance_id:
                            logger.info(f"Processing switch command: {cmd['target_mode']}")
                            
                            # Map 'pool' to 'spot' for compatibility
                            target_mode = 'spot' if cmd['target_mode'] == 'pool' else cmd['target_mode']
                            
                            success = self.execute_switch(
                                target_mode=target_mode,
                                target_pool_id=cmd.get('target_pool_id'),
                                trigger='manual'
                            )
                            
                            if success:
                                logger.info(f"✓ Switch completed successfully")
                            else:
                                logger.error(f"✗ Switch failed")
                            
                            # Mark command as executed
                            self.server_client.mark_command_executed(cmd['id'])
                
            except Exception as e:
                logger.error(f"Command processor error: {e}")
            
            self.stop_event.wait(self.config.command_check_interval)
    
    def execute_switch(self, target_mode: str, target_pool_id: Optional[str], trigger: str) -> bool:
        """Execute instance switch - FULLY COMPATIBLE WITH BACKEND"""
        with self.switch_lock:
            if self.switching_in_progress:
                logger.warning("Switch already in progress")
                return False
            
            self.switching_in_progress = True
        
        try:
            logger.info("="*80)
            logger.info(f"STARTING INSTANCE SWITCH: {self.current_mode} -> {target_mode}")
            logger.info("="*80)
            
            old_instance_id = self.config.instance_id
            old_mode = self.current_mode
            old_pool_id = self.current_pool_id
            
            # Step 1: Get current instance details
            logger.info("Step 1: Getting instance details...")
            instance_details = self.resource_manager.get_instance_details(old_instance_id)
            if not instance_details:
                logger.error("Failed to get instance details")
                return False
            
            logger.info(f"✓ Retrieved instance details")
            
            # Step 2: Create AMI
            logger.info("Step 2: Creating AMI snapshot...")
            ami_id = self.resource_manager.create_ami_from_instance(
                old_instance_id,
                f"spot-optimizer-{old_instance_id}"
            )
            if not ami_id:
                logger.error("Failed to create AMI")
                return False
            
            logger.info(f"✓ AMI created: {ami_id}")
            
            # Step 3: Prepare launch configuration
            logger.info("Step 3: Preparing launch configuration...")
            launch_config = {
                'ami_id': ami_id,
                'instance_type': instance_details['instance_type'],
                'key_name': instance_details.get('key_name'),
                'security_groups': instance_details['security_groups'],
                'subnet_id': instance_details['subnet_id'],
                'iam_instance_profile': instance_details.get('iam_instance_profile'),
                'tags': instance_details['tags'],
                'network_interfaces': instance_details.get('network_interfaces', []),
                'old_instance_id': old_instance_id
            }
            
            logger.info(f"✓ Launch configuration prepared")
            
            # Step 4: Launch new instance
            logger.info(f"Step 4: Launching new {target_mode} instance...")
            timing_start = datetime.utcnow()
            
            new_instance_id = self.resource_manager.launch_instance(
                launch_config,
                target_mode,
                target_pool_id
            )
            
            if not new_instance_id:
                logger.error("Failed to launch new instance")
                return False
            
            timing_ready = datetime.utcnow()
            logger.info(f"✓ New instance launched: {new_instance_id}")
            
            # Step 5: Get new instance details
            logger.info("Step 5: Verifying new instance...")
            time.sleep(5)  # Wait for instance to stabilize
            new_details = self.resource_manager.get_instance_details(new_instance_id)
            if not new_details:
                logger.error("Failed to get new instance details")
                return False
            
            new_mode, new_pool_id = self.resource_manager.get_current_mode(new_instance_id)
            logger.info(f"✓ New instance mode: {new_mode}")
            
            # Step 6: Get pricing information
            logger.info("Step 6: Getting pricing information...")
            on_demand_price = self._get_ondemand_price()
            
            spot_pools = self.resource_manager.get_spot_prices(self.config.instance_type)
            old_spot_price = 0.0
            new_spot_price = 0.0
            
            if old_mode == 'spot' and old_pool_id:
                old_pool = next((p for p in spot_pools if p['pool_id'] == old_pool_id), None)
                if old_pool:
                    old_spot_price = old_pool['price']
            
            if new_mode == 'spot' and new_pool_id:
                new_pool = next((p for p in spot_pools if p['pool_id'] == new_pool_id), None)
                if new_pool:
                    new_spot_price = new_pool['price']
            
            logger.info(f"✓ Pricing: On-Demand=${on_demand_price:.6f}, Old Spot=${old_spot_price:.6f}, New Spot=${new_spot_price:.6f}")
            
            # Step 7: Terminate old instance (if enabled)
            timing_switched = datetime.utcnow()
            
            if self.config.auto_terminate_enabled:
                logger.info(f"Step 7: Terminating old instance {old_instance_id}...")
                terminate_success = self.resource_manager.terminate_instance(old_instance_id)
                if terminate_success:
                    logger.info(f"✓ Old instance terminated")
                    timing_terminated = datetime.utcnow()
                else:
                    logger.warning(f"Failed to terminate old instance")
                    timing_terminated = None
            else:
                logger.info("Step 7: Auto-terminate disabled, keeping old instance")
                timing_terminated = None
            
            # Step 8: Report switch to server - BACKEND COMPATIBLE FORMAT
            logger.info("Step 8: Reporting switch to server...")
            
            report_success = self.server_client.report_switch_event(
                old_instance={
                    'instance_id': old_instance_id,
                    'mode': old_mode,
                    'pool_id': old_pool_id,
                    'instance_type': instance_details['instance_type'],
                    'region': self.config.region,
                    'az': instance_details['az'],
                    'ami_id': instance_details['tags'].get('ami-id', self.config.ami_id)
                },
                new_instance={
                    'instance_id': new_instance_id,
                    'mode': new_mode,
                    'pool_id': new_pool_id,
                    'instance_type': new_details['instance_type'],
                    'region': self.config.region,
                    'az': new_details['az'],
                    'ami_id': ami_id
                },
                snapshot={
                    'used': True,
                    'snapshot_id': ami_id
                },
                prices={
                    'on_demand': on_demand_price,
                    'old_spot': old_spot_price,
                    'new_spot': new_spot_price
                },
                timing={
                    'switch_initiated_at': timing_start.isoformat(),
                    'new_instance_ready_at': timing_ready.isoformat(),
                    'traffic_switched_at': timing_switched.isoformat(),
                    'old_instance_terminated_at': timing_terminated.isoformat() if timing_terminated else None
                },
                trigger=trigger
            )
            
            if report_success:
                logger.info(f"✓ Switch reported to server")
            else:
                logger.warning(f"Failed to report switch to server")
            
            # Step 9: Update agent configuration
            logger.info("Step 9: Updating agent configuration...")
            self.config.instance_id = new_instance_id
            self.config.instance_type = new_details['instance_type']
            self.config.availability_zone = new_details['az']
            self.current_mode = new_mode
            self.current_pool_id = new_pool_id
            
            logger.info(f"✓ Agent now monitoring: {new_instance_id}")
            
            logger.info("="*80)
            logger.info(f"✓ SWITCH COMPLETED SUCCESSFULLY")
            logger.info(f"  Old: {old_instance_id} ({old_mode})")
            logger.info(f"  New: {new_instance_id} ({new_mode})")
            logger.info("="*80)
            
            return True
            
        except Exception as e:
            logger.error(f"Switch execution failed: {e}", exc_info=True)
            return False
        
        finally:
            self.switching_in_progress = False
    
    def _get_ondemand_price(self) -> float:
        """Get cached or fetch on-demand price"""
        if self.last_ondemand_price and self.last_ondemand_fetch:
            age = (datetime.utcnow() - self.last_ondemand_fetch).total_seconds()
            if age < self.config.ondemand_price_interval:
                return self.last_ondemand_price
        
        price = self.resource_manager.get_ondemand_price(self.config.instance_type)
        if price:
            self.last_ondemand_price = price
            self.last_ondemand_fetch = datetime.utcnow()
        
        return self.last_ondemand_price or 0.1
    
    def run(self):
        """Main run loop"""
        try:
            self.initialize()
            self.start_monitoring_threads()
            
            logger.info("🚀 Agent is now running...")
            logger.info("Press Ctrl+C to stop")
            
            while not self.stop_event.is_set():
                self.stop_event.wait(10)
            
        except KeyboardInterrupt:
            logger.info("\n⏹️  Shutdown signal received")
        except Exception as e:
            logger.error(f"Fatal error: {e}", exc_info=True)
        finally:
            self.shutdown()
    
    def shutdown(self):
        """Shutdown agent gracefully"""
        logger.info("Shutting down agent...")
        
        try:
            self.server_client.send_heartbeat(status='offline')
        except:
            pass
        
        self.stop_event.set()
        
        for thread in self.threads:
            thread.join(timeout=5)
        
        logger.info("✓ Agent stopped")

def main():
    """Main entry point"""
    config = AgentConfig()
    
    if not config.client_token:
        logger.error("CLIENT_TOKEN not set in environment")
        sys.exit(1)
    
    if not config.central_server_url:
        logger.error("CENTRAL_SERVER_URL not set in environment")
        sys.exit(1)
    
    agent = SpotOptimizerAgent(config)
    agent.run()

if __name__ == '__main__':
    main()
