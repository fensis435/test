set -ueo pipefail
./bin/sqs_poller &
./bin/rails server -b 0.0.0.0 -p 3001
