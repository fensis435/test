cd oidc-dev-server
./build-docker.sh
cd ..

cd cognito-local
docker compose build
cd ..

cd oidc-web-test/frontend/
npm install
[ -f .env ] || cp .env.example .env
cd ../../

cd oidc-web-test/backend/
bundle install
[ -f .env ] || cp .env.example .env
cd ../../

