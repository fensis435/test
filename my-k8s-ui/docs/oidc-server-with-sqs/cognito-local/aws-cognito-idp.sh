if [ $# -lt 1 ]; then
  echo "`basename $0` (cognito-idp command) (params...)"
  exit 1
fi
source .env
CMD=$1
shift
set -x
aws cognito-idp $CMD --user-pool-id $USER_POOL_ID $*
