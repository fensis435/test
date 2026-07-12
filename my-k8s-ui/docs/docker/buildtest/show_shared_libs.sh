docker buildx build --provenance=false -f Dockerfile.ruby-app --target deps -t ruby-deps-debug .
docker create --name tmp-deps ruby-deps-debug
docker cp tmp-deps:/tmp/deps/shared_libs.txt ./ruby_shared_libs.txt
docker rm tmp-deps
echo "=== ruby ==="
cat ruby_shared_libs.txt

docker buildx build --provenance=false -f Dockerfile.python-app --target deps -t python-deps-debug .
docker create --name tmp-deps python-deps-debug
docker cp tmp-deps:/tmp/deps/shared_libs.txt ./python_shared_libs.txt
docker rm tmp-deps
echo "=== python ==="
cat python_shared_libs.txt
