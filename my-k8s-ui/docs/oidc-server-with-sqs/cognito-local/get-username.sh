set -euo pipefail

source .env
USERNAME=${1:-testuser1@examle.com}

aws cognito-idp list-users \
  --user-pool-id ${USER_POOL_ID} \
  --filter 'email = "'${USERNAME}'"' \
  --query "Users[0].Username" \
  --output text
