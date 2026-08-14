set -euo pipefail

source .env

aws cognito-idp delete-user-pool --user-pool-id ${USER_POOL_ID}
aws cognito-idp list-user-pools --max-results 20
rm -f .env
