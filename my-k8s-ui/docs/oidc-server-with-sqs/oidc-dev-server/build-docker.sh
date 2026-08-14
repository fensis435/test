set -xueo pipefail

if [ ! -f .env ]; then
  KEY1=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
  KEY2=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
  cat .env.example | sed 's/dev-cookie-secret-key-please-change/'${KEY1}'/g'| sed 's/dev-admin-jwt-secret-please-change/'${KEY2}'/g' > .env
fi

docker compose down -v || true
docker compose build
docker compose --profile jwks run --rm jwks
docker compose --profile migrate run --rm migrate
docker compose --profile seed run --rm -e SEED_ADMIN_PASSWORD=change-me-please -e SEED_TEST_USER_PASSWORD=test-password-1234 seed
docker compose up -d oidc-dev-server

sleep 10
set +x

echo
echo "==== regist redirect uri ===="
ruby ../oidc-web-test/scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback \
  --post-logout-redirect-uri https://app.dev.test/ \
  --update
