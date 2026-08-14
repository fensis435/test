set -euo pipefail

source .env

USER1_EMAIL=testuser1@example.com
USER1_NAME=$USER1_EMAIL
USER1_PASSWD=testuser123
USER2_EMAIL=testuser2@example.com
USER2_NAME=$USER2_EMAIL
USER2_PASSWD=testuser123

GROUP1_NAME=group1_proj1
GROUP2_NAME=group2_proj2

aws cognito-idp create-group \
  --user-pool-id ${USER_POOL_ID} \
  --group-name ${GROUP1_NAME}

aws cognito-idp create-group \
  --user-pool-id ${USER_POOL_ID} \
  --group-name ${GROUP2_NAME}

aws cognito-idp admin-create-user \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER1_NAME} \
  --user-attributes Name=email,Value=${USER1_EMAIL} Name=email_verified,Value=true \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER1_NAME} \
  --password ${USER1_PASSWD} \
  --permanent

aws cognito-idp admin-create-user \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER2_NAME} \
  --user-attributes Name=email,Value=${USER2_EMAIL} Name=email_verified,Value=true \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER2_NAME} \
  --password ${USER2_PASSWD} \
  --permanent

USER1_ID=$(
aws cognito-idp list-users \
  --user-pool-id ${USER_POOL_ID} \
  --filter 'email = "'${USER1_NAME}'"' \
  --query "Users[0].Username" \
  --output text \
)

USER2_ID=$(
aws cognito-idp list-users \
  --user-pool-id ${USER_POOL_ID} \
  --filter 'email = "'${USER2_NAME}'"' \
  --query "Users[0].Username" \
  --output text \
)

aws cognito-idp admin-add-user-to-group \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER1_ID} \
  --group-name ${GROUP1_NAME}

aws cognito-idp admin-add-user-to-group \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER2_ID} \
  --group-name ${GROUP2_NAME}

aws cognito-idp list-users \
  --user-pool-id ${USER_POOL_ID}

aws cognito-idp list-groups \
  --user-pool-id ${USER_POOL_ID}

aws cognito-idp admin-list-groups-for-user \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER1_ID}

aws cognito-idp admin-list-groups-for-user \
  --user-pool-id ${USER_POOL_ID} \
  --username ${USER2_ID}
