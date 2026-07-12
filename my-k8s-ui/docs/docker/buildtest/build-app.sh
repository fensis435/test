set -eux

# Rubyアプリ
docker buildx build $* --provenance=false -f Dockerfile.ruby-app -t ruby-testapp .

# Pythonアプリ
docker buildx build $* --provenance=false -f Dockerfile.python-app -t python-testapp .
