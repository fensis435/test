#!/usr/bin/env bash
# Delete everything created by deploy.sh (the whole CloudFormation stack).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-p sso-profile] [-r region] [-s stack-name] [-d] [-y] [-h]
  -p  AWS SSO profile (default: \$AWS_PROFILE)
  -r  Region
  -s  Stack name (default: ${STACK_NAME})
  -d  Use device-code flow for 'aws sso login'
  -y  Do not ask for confirmation
NOTE: resources created later by the EKS builder role (EKS, ENIs, SGs, NAT GW,
VPC endpoints, load balancers ... inside this VPC) are NOT part of this stack and
must be deleted first, otherwise the VPC deletion fails.
EOF
}

parse_args "$@"
require_cmds aws
setup_proxy
setup_aws

status="$(stack_status)"
if [[ "$status" == NOT_FOUND ]]; then
  log "stack $STACK_NAME does not exist. Nothing to do."
  exit 0
fi
[[ "$status" == *_IN_PROGRESS ]] && die "stack is busy ($status). Wait and retry."

log "resources that will be deleted:"
aws cloudformation list-stack-resources --stack-name "$STACK_NAME" \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,PhysicalResourceId]' --output table >&2
confirm "Delete stack $STACK_NAME?" || die "aborted"

VPC_ID="$(aws cloudformation describe-stack-resource --stack-name "$STACK_NAME" \
  --logical-resource-id Vpc --query 'StackResourceDetail.PhysicalResourceId' --output text 2>/dev/null || true)"

if ! delete_stack_and_wait; then
  if [[ -n "$VPC_ID" && "$VPC_ID" != None ]]; then
    warn "Remaining dependencies in $VPC_ID (delete these, then rerun this script):"
    aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'NetworkInterfaces[].[NetworkInterfaceId,Description,Status]' --output table >&2 || true
    aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
      --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName,Description]" --output table >&2 || true
    aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'VpcEndpoints[].[VpcEndpointId,ServiceName,State]' --output table >&2 || true
    aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
      --query 'NatGateways[].[NatGatewayId,State]' --output table >&2 || true
  fi
  die "stack deletion failed"
fi
log "stack $STACK_NAME deleted."
