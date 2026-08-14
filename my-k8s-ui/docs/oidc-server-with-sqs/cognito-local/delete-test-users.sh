#set -ueo pipefail

source .env

USER1_NAME=testuser1@examle.com
USER2_NAME=testuser2@examle.com

GROUP1_NAME=group1_proj1
GROUP2_NAME=group2_proj2

aws cognito-idp admin-delete-user \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER1_NAME}

aws cognito-idp admin-delete-user \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER2_NAME}

aws cognito-idp delete-group \
  --user-pool-id ${USER_POOL_ID} \
  --group-name  ${GROUP1_NAME}

aws cognito-idp delete-group \
  --user-pool-id ${USER_POOL_ID} \
  --group-name  ${GROUP2_NAME}

aws cognito-idp list-users \
  --user-pool-id ${USER_POOL_ID}
