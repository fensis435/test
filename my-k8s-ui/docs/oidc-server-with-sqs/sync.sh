#rsync -av --update vaio@192.168.0.36:~/oidc-server-with-sqs/ .
set -x
rsync -avi --update --dry-run vaio@192.168.0.36:~/oidc-server-with-sqs/ .
