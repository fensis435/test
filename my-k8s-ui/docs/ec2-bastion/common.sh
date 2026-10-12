#!/usr/bin/env bash
# Shared helpers for deploy.sh / cleanup.sh (sourced, not executed)

log()  { printf '\033[32m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- defaults (override with options or environment) -------------------
STACK_NAME="${STACK_NAME:-eks-bastion-ec2}"
TEMPLATE="${TEMPLATE:-$ROOT/bastion-ec2.yaml}"
PARAMS="${PARAMS:-$ROOT/bastion-params.json}"
PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
DEVICE_CODE=0
ASSUME_YES=0
SSH_KEY_FILE="${SSH_KEY_FILE:-}"

parse_args() {
  local opt
  OPTIND=1
  while getopts "p:r:s:t:f:k:dyh" opt; do
    case "$opt" in
      k) SSH_KEY_FILE="$OPTARG" ;;
      p) PROFILE="$OPTARG" ;;
      r) REGION="$OPTARG" ;;
      s) STACK_NAME="$OPTARG" ;;
      t) TEMPLATE="$OPTARG" ;;
      f) PARAMS="$OPTARG" ;;
      d) DEVICE_CODE=1 ;;
      y) ASSUME_YES=1 ;;
      h) usage; exit 0 ;;
      *) usage; exit 2 ;;
    esac
  done
}

require_cmds() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' not found. (Ubuntu: sudo apt-get install -y $c)"
  done
}

# ---- proxy: make upper/lower case variants consistent for the AWS CLI ---
setup_proxy() {
  local v lower
  for v in HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    lower="$(printf '%s' "$v" | tr 'A-Z' 'a-z')"
    if [[ -z "${!v:-}" && -n "${!lower:-}" ]]; then
      export "$v=${!lower}"
    fi
    if [[ -n "${!v:-}" && -z "${!lower:-}" ]]; then
      export "$lower=${!v}"
    fi
  done
  if [[ -n "${HTTPS_PROXY:-}" ]]; then
    log "proxy: HTTPS_PROXY=${HTTPS_PROXY}"
  else
    warn "HTTPS_PROXY is not set. If you are behind a corporate proxy, export HTTPS_PROXY first."
  fi
  if [[ -n "${AWS_CA_BUNDLE:-}" && ! -f "$AWS_CA_BUNDLE" ]]; then
    die "AWS_CA_BUNDLE points to a missing file: $AWS_CA_BUNDLE"
  fi
}

# ---- AWS session (SSO) ---------------------------------------------------
setup_aws() {
  export AWS_PAGER=""
  [[ -n "$PROFILE" ]] && export AWS_PROFILE="$PROFILE"
  [[ -n "$REGION"  ]] && export AWS_DEFAULT_REGION="$REGION"

  local out
  if ! out="$(aws sts get-caller-identity 2>&1)"; then
    warn "AWS credentials are not usable: ${out%%$'\n'*}"
    [[ -n "$PROFILE" ]] || die "No profile given. Use -p <sso-profile> or export AWS_PROFILE, then retry."
    local args=(sso login --profile "$PROFILE")
    (( DEVICE_CODE )) && args+=(--use-device-code)
    log "aws ${args[*]}"
    aws "${args[@]}"
  fi
  aws sts get-caller-identity --query '[Account,Arn]' --output text >&2 \
    || die "Still unable to authenticate."

  if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
    REGION="$(aws configure get region 2>/dev/null || true)"
    [[ -n "$REGION" ]] || die "Region is not set. Use -r <region> or set it in the profile."
    export AWS_DEFAULT_REGION="$REGION"
  fi
  log "profile=${AWS_PROFILE:-<default>} region=$AWS_DEFAULT_REGION stack=$STACK_NAME"
}

# ---- CloudFormation helpers --------------------------------------------
# prints stack status, or NOT_FOUND
stack_status() {
  local out
  if out="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
        --query 'Stacks[0].StackStatus' --output text 2>&1)"; then
    printf '%s\n' "$out"
  elif [[ "$out" == *"does not exist"* ]]; then
    echo NOT_FOUND
  else
    printf '%s\n' "$out" >&2
    return 1
  fi
}

show_failures() {
  warn "Failed stack events:"
  aws cloudformation describe-stack-events --stack-name "$STACK_NAME" \
    --query "StackEvents[?contains(ResourceStatus,'FAILED')].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]" \
    --output table >&2 || true
}

# wait_stack create|update|delete
wait_stack() {
  local op="$1"
  log "waiting for stack-${op}-complete (this can take several minutes)..."
  if ! aws cloudformation wait "stack-${op}-complete" --stack-name "$STACK_NAME"; then
    show_failures
    return 1
  fi
}

delete_stack_and_wait() {
  log "deleting stack $STACK_NAME"
  aws cloudformation delete-stack --stack-name "$STACK_NAME"
  wait_stack delete
}

stack_output() {
  aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

confirm() {
  (( ASSUME_YES )) && return 0
  local ans
  read -r -p "$1 [y/N]: " ans
  [[ "$ans" == y || "$ans" == Y || "$ans" == yes ]]
}
