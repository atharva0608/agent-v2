#!/bin/bash
# ============================================================================
# AWS Spot Optimizer - Cleanup Script
# ============================================================================
# This script cleans up old snapshots and AMIs created by Spot Optimizer
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default values
SNAPSHOT_DAYS=${SNAPSHOT_DAYS:-7}
AMI_DAYS=${AMI_DAYS:-30}
DRY_RUN=${DRY_RUN:-true}
REGION=${AWS_REGION:-us-east-1}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --snapshot-days)
            SNAPSHOT_DAYS="$2"
            shift 2
            ;;
        --ami-days)
            AMI_DAYS="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --execute)
            DRY_RUN=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --snapshot-days N   Delete snapshots older than N days (default: 7)"
            echo "  --ami-days N        Delete AMIs older than N days (default: 30)"
            echo "  --region REGION     AWS region (default: us-east-1)"
            echo "  --execute           Actually delete (default: dry-run)"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "============================================"
echo "  Spot Optimizer Cleanup Script"
echo "============================================"
echo ""
log_info "Region: $REGION"
log_info "Snapshot retention: $SNAPSHOT_DAYS days"
log_info "AMI retention: $AMI_DAYS days"
if [ "$DRY_RUN" = "true" ]; then
    log_warn "DRY RUN MODE - No resources will be deleted"
fi
echo ""

# Calculate cutoff dates
SNAPSHOT_CUTOFF=$(date -d "$SNAPSHOT_DAYS days ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -v-${SNAPSHOT_DAYS}d +%Y-%m-%dT%H:%M:%S)
AMI_CUTOFF=$(date -d "$AMI_DAYS days ago" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -v-${AMI_DAYS}d +%Y-%m-%dT%H:%M:%S)

# ============================================================================
# CLEANUP SNAPSHOTS
# ============================================================================

log_info "Finding old snapshots..."

SNAPSHOTS=$(aws ec2 describe-snapshots \
    --region "$REGION" \
    --owner-ids self \
    --filters "Name=tag:ManagedBy,Values=SpotOptimizer" \
    --query "Snapshots[?StartTime<='$SNAPSHOT_CUTOFF'].SnapshotId" \
    --output text)

SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | wc -w)
log_info "Found $SNAPSHOT_COUNT snapshots to delete"

DELETED_SNAPSHOTS=0
FAILED_SNAPSHOTS=0

for SNAPSHOT_ID in $SNAPSHOTS; do
    if [ -z "$SNAPSHOT_ID" ] || [ "$SNAPSHOT_ID" = "None" ]; then
        continue
    fi

    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY RUN] Would delete snapshot: $SNAPSHOT_ID"
    else
        if aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$SNAPSHOT_ID" 2>/dev/null; then
            echo "  Deleted snapshot: $SNAPSHOT_ID"
            ((DELETED_SNAPSHOTS++))
        else
            log_warn "  Failed to delete snapshot: $SNAPSHOT_ID"
            ((FAILED_SNAPSHOTS++))
        fi
    fi
done

# ============================================================================
# CLEANUP AMIs
# ============================================================================

log_info "Finding old AMIs..."

AMIS=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners self \
    --filters "Name=tag:ManagedBy,Values=SpotOptimizer" \
    --query "Images[?CreationDate<='$AMI_CUTOFF'].[ImageId,BlockDeviceMappings[*].Ebs.SnapshotId]" \
    --output json)

AMI_COUNT=$(echo "$AMIS" | jq -r 'length')
log_info "Found $AMI_COUNT AMIs to delete"

DELETED_AMIS=0
DELETED_AMI_SNAPSHOTS=0
FAILED_AMIS=0

for row in $(echo "$AMIS" | jq -r '.[] | @base64'); do
    _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
    }

    AMI_ID=$(_jq '.[0]')
    SNAPSHOT_IDS=$(_jq '.[1][]')

    if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "null" ]; then
        continue
    fi

    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY RUN] Would deregister AMI: $AMI_ID"
        for SNAP_ID in $SNAPSHOT_IDS; do
            echo "  [DRY RUN] Would delete associated snapshot: $SNAP_ID"
        done
    else
        # Deregister AMI
        if aws ec2 deregister-image --region "$REGION" --image-id "$AMI_ID" 2>/dev/null; then
            echo "  Deregistered AMI: $AMI_ID"
            ((DELETED_AMIS++))

            # Delete associated snapshots
            for SNAP_ID in $SNAPSHOT_IDS; do
                if [ -n "$SNAP_ID" ] && [ "$SNAP_ID" != "null" ]; then
                    sleep 1  # Small delay to ensure AMI is fully deregistered
                    if aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$SNAP_ID" 2>/dev/null; then
                        echo "    Deleted associated snapshot: $SNAP_ID"
                        ((DELETED_AMI_SNAPSHOTS++))
                    fi
                fi
            done
        else
            log_warn "  Failed to deregister AMI: $AMI_ID"
            ((FAILED_AMIS++))
        fi
    fi
done

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "============================================"
echo "  Cleanup Summary"
echo "============================================"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    log_warn "DRY RUN - No resources were actually deleted"
    echo ""
    echo "To execute cleanup, run with --execute flag:"
    echo "  $0 --execute"
else
    log_success "Cleanup completed"
    echo ""
    echo "Snapshots deleted: $DELETED_SNAPSHOTS (failed: $FAILED_SNAPSHOTS)"
    echo "AMIs deregistered: $DELETED_AMIS (failed: $FAILED_AMIS)"
    echo "AMI snapshots deleted: $DELETED_AMI_SNAPSHOTS"
fi
echo ""
