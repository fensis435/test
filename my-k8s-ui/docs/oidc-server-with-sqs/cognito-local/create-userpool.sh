set -euo pipefail

USER_POOL_ID=$(
  aws cognito-idp create-user-pool \
    --pool-name UserPool \
    --query UserPool.Id \
    --output text \
)
aws cognito-idp list-user-pools --max-results 20
CLIENT_ID=$(
  aws cognito-idp create-user-pool-client \
    --client-name MyUserPoolClient \
    --user-pool-id ${USER_POOL_ID} \
    --query UserPoolClient.ClientId \
    --output text \
)
cat>.env<<EOF
USER_POOL_ID=$USER_POOL_ID
CLIENT_ID=$CLIENT_ID
EOF
