#!/usr/bin/env bash
# Create or update the bastion EC2 CloudFormation stack.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-p sso-profile] [-r region] [-s stack-name] [-t template.yaml] [-f params.json] [-k ssh-public-key-file] [-d] [-y] [-h]
  -p  AWS SSO profile (default: \$AWS_PROFILE)
  -r  Region (default: \$AWS_REGION / profile region)
  -s  Stack name (default: ${STACK_NAME})
  -t  CFn template (default: bastion-ec2.yaml)
  -f  CFn parameter JSON (default: bastion-params.json)
  -k  SSH public key to install for user 'ec2-user'
      (default: ~/.ssh/id_ed25519.pub, then ~/.ssh/id_rsa.pub, unless SshPublicKey is set in the JSON)
  -d  Use device-code flow for 'aws sso login' (no local browser)
  -y  Do not ask for confirmation
Network mode is chosen with "NetworkMode" in the parameter JSON: Internet | Private.
Behind a proxy: export HTTPS_PROXY / NO_PROXY (and AWS_CA_BUNDLE if TLS is inspected).
Stack missing -> create, stack exists -> update.
EOF
}

parse_args "$@"
require_cmds aws jq
[[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE"
[[ -f "$PARAMS"   ]] || die "parameter file not found: $PARAMS"
TEMPLATE="$(cd "$(dirname "$TEMPLATE")" && pwd)/$(basename "$TEMPLATE")"
PARAMS="$(cd "$(dirname "$PARAMS")" && pwd)/$(basename "$PARAMS")"

# ---- validate parameter file -------------------------------------------
jq -e 'type=="array" and all(.[]; has("ParameterKey") and has("ParameterValue"))' "$PARAMS" >/dev/null \
  || die "$PARAMS must be CloudFormation parameter format: [{\"ParameterKey\":..,\"ParameterValue\":..}]"

# Work on a copy: values discovered below (CIDR, route tables, ssh key) never touch the user's file.
EFFECTIVE_PARAMS="$(mktemp)"
trap 'rm -f "$EFFECTIVE_PARAMS"' EXIT
cp "$PARAMS" "$EFFECTIVE_PARAMS"

pval() { jq -r --arg k "$1" '.[] | select(.ParameterKey==$k) | .ParameterValue // ""' "$EFFECTIVE_PARAMS"; }
set_param() {
  local tmp; tmp="$(mktemp)"
  jq --arg k "$1" --arg v "$2" \
    'map(select(.ParameterKey!=$k)) + [{ParameterKey:$k,ParameterValue:$v}]' "$EFFECTIVE_PARAMS" > "$tmp" \
    && mv "$tmp" "$EFFECTIVE_PARAMS"
}

MODE="$(pval NetworkMode)"; MODE="${MODE:-Internet}"
case "$MODE" in Internet|Private) ;; *) die "NetworkMode must be Internet or Private (got: $MODE)";; esac
VPC_ID_PARAM="$(pval VpcId)"
SUBNET_ID_PARAM="$(pval SubnetId)"
if [[ -n "$VPC_ID_PARAM" && -z "$SUBNET_ID_PARAM" ]]; then
  die "VpcId is set but SubnetId is empty. Specify a subnet (Internet: outbound access / Private: private subnet)."
fi
[[ -z "$VPC_ID_PARAM" && -n "$SUBNET_ID_PARAM" ]] && die "SubnetId is set but VpcId is empty."
log "network mode: $MODE ($([[ -n "$VPC_ID_PARAM" ]] && echo "existing VPC $VPC_ID_PARAM" || echo "new VPC"))"

if [[ "$MODE" == Private && -z "$(pval HttpProxy)" ]]; then
  warn "Private mode without HttpProxy: kubectl / eksctl / helm will NOT be installed on the bastion (aws cli is part of the AMI)."
  warn "Copy them over SSH afterwards (see README), or set HttpProxy to a proxy reachable from the VPC."
fi

# ---- SSH public key (for SSH over SSM) ------------------------------------
if [[ -z "$(pval SshPublicKey)" ]]; then
  key_file="$SSH_KEY_FILE"
  if [[ -z "$key_file" ]]; then
    for c in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
      [[ -f "$c" ]] && { key_file="$c"; break; }
    done
  fi
  if [[ -n "$key_file" ]]; then
    [[ -f "$key_file" ]] || die "ssh public key file not found: $key_file"
    key="$(awk 'NR==1{print $1" "$2}' "$key_file")"   # drop the comment
    [[ "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\ [A-Za-z0-9+/=]+$ ]] \
      || die "unsupported / malformed public key in $key_file"
    set_param SshPublicKey "$key"
    SSH_KEY_FILE="$key_file"
    log "ssh public key: $key_file"
  else
    warn "No SSH public key found. Only the SSM shell will work (pass -k <file.pub> or run ssh-keygen -t ed25519)."
  fi
fi

setup_proxy
setup_aws

# ---- existing VPC: look up what the endpoints need ---------------------------
if [[ -n "$VPC_ID_PARAM" && "$MODE" == Private && "$(pval CreateVpcEndpoints)" != false ]]; then
  if [[ -z "$(pval ExistingVpcCidr)" ]]; then
    cidr="$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID_PARAM" --query 'Vpcs[0].CidrBlock' --output text)" \
      || die "cannot read the CIDR of $VPC_ID_PARAM (set ExistingVpcCidr manually)"
    log "ExistingVpcCidr = $cidr"
    set_param ExistingVpcCidr "$cidr"
  fi
  if [[ -z "$(pval RouteTableIds)" ]]; then
    rt="$(aws ec2 describe-route-tables \
            --filters "Name=association.subnet-id,Values=$SUBNET_ID_PARAM" \
            --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || true)"
    if [[ -z "$rt" || "$rt" == None ]]; then   # subnet uses the VPC main route table
      rt="$(aws ec2 describe-route-tables \
              --filters "Name=vpc-id,Values=$VPC_ID_PARAM" "Name=association.main,Values=true" \
              --query 'RouteTables[0].RouteTableId' --output text)" \
        || die "cannot find the route table of $SUBNET_ID_PARAM (set RouteTableIds manually)"
    fi
    log "RouteTableIds   = $rt (S3 gateway endpoint)"
    set_param RouteTableIds "$rt"
  fi
fi

log "validating template"
aws cloudformation validate-template --template-body "file://$TEMPLATE" >/dev/null

COMMON_ARGS=(
  --stack-name "$STACK_NAME"
  --template-body "file://$TEMPLATE"
  --parameters "file://$EFFECTIVE_PARAMS"
  --capabilities CAPABILITY_IAM
)

status="$(stack_status)"
log "current stack status: $status"

# states that cannot be updated in place -> recreate
case "$status" in
  ROLLBACK_COMPLETE|CREATE_FAILED|REVIEW_IN_PROGRESS|DELETE_FAILED)
    warn "stack is in $status; it must be deleted before it can be created again."
    confirm "Delete stack $STACK_NAME and recreate?" || die "aborted"
    delete_stack_and_wait || die "delete failed. Resolve the blockers and run cleanup.sh"
    status=NOT_FOUND
    ;;
  *_IN_PROGRESS)
    die "stack is busy ($status). Wait for it to finish and retry." ;;
  UPDATE_ROLLBACK_FAILED)
    die "stack is UPDATE_ROLLBACK_FAILED. Run: aws cloudformation continue-update-rollback --stack-name $STACK_NAME" ;;
esac

# Existing VPC + Private: warn about endpoints that would collide on private DNS.
if [[ "$status" == NOT_FOUND && -n "$VPC_ID_PARAM" && "$MODE" == Private && "$(pval CreateVpcEndpoints)" != false ]]; then
  existing="$(aws ec2 describe-vpc-endpoints \
      --filters "Name=vpc-id,Values=$VPC_ID_PARAM" "Name=vpc-endpoint-state,Values=available,pending" \
      --query 'VpcEndpoints[].ServiceName' --output text 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    warn "VPC $VPC_ID_PARAM already has endpoints: $existing"
    warn "Creating the same service again with private DNS fails. If so, set CreateVpcEndpoints=false (or delete the old ones)."
  fi
fi

if [[ "$status" == NOT_FOUND ]]; then
  log "creating stack"
  aws cloudformation create-stack "${COMMON_ARGS[@]}" \
    --tags "Key=ManagedBy,Value=bastion-deploy-sh" >/dev/null
  wait_stack create || die "create failed (stack was rolled back; run cleanup.sh before retrying)"
else
  log "updating stack"
  if ! out="$(aws cloudformation update-stack "${COMMON_ARGS[@]}" 2>&1)"; then
    if [[ "$out" == *"No updates are to be performed"* ]]; then
      log "no changes to apply"
    else
      die "update-stack failed: $out"
    fi
  else
    wait_stack update || die "update failed (CloudFormation rolled back)"
  fi
fi

# ---- outputs -------------------------------------------------------------
echo >&2
aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table >&2

INSTANCE_ID="$(stack_output InstanceId)"

# wait (best effort) until the SSM agent registers
log "waiting for SSM agent on $INSTANCE_ID (up to 5 min, non-fatal)"
online=0
for _ in $(seq 1 30); do
  ping="$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
  if [[ "$ping" == Online ]]; then online=1; break; fi
  sleep 10
done
(( online )) && log "SSM: Online" || warn "SSM not Online yet (bootstrap may still be running / no ssm permission for your SSO role)"

PROFILE_OPT=""; [[ -n "${AWS_PROFILE:-}" ]] && PROFILE_OPT=" --profile $AWS_PROFILE"
REGION_OPT=" --region $AWS_DEFAULT_REGION"
IDENTITY_LINE=""
[[ -n "$SSH_KEY_FILE" ]] && IDENTITY_LINE="  IdentityFile ${SSH_KEY_FILE%.pub}"$'\n'

cat >&2 <<EOF

--- Next steps -----------------------------------------------------------
# 1) Shell through SSM (needs the Session Manager plugin on this machine)
aws ssm start-session --target $INSTANCE_ID$REGION_OPT$PROFILE_OPT

# 2) SSH through SSM  -> add to ~/.ssh/config, then: ssh eks-bastion
Host eks-bastion
  HostName $INSTANCE_ID
  User ec2-user
${IDENTITY_LINE}  ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p$REGION_OPT$PROFILE_OPT

# 2') or an explicit port forward (terminal 1), then ssh -p 2222 ec2-user@localhost (terminal 2)
aws ssm start-session --target $INSTANCE_ID$REGION_OPT$PROFILE_OPT \\
  --document-name AWS-StartPortForwardingSession \\
  --parameters '{"portNumber":["22"],"localPortNumber":["2222"]}'

# 3) Reach a private Web UI through the bastion over SSH
ssh -L 8443:<private-host-name>:443 eks-bastion        # then open https://localhost:8443

# On the bastion: shell with the EKS builder role (assume-role) active
eks-builder-shell
--------------------------------------------------------------------------
EOF
