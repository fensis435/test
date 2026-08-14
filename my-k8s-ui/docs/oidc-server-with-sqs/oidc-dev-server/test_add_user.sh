export OIDC_ISSUER=https://idp.dev.test
export ADMIN_EMAIL=admin@example.com
export ADMIN_PASSWORD=change-me-please
PASSWD=correct-horse-battery
EMAIL=new@example.com
ruby scripts/manage_users.rb create --email $EMAIL --password $PASSWD
