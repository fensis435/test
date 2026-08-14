mkdir -p ~/.aws
cat >~/.aws/credentials<<EOF
[local]
aws_access_key_id = dummy
aws_secret_access_key = dummy
EOF
cat >~/.aws/config<<EOF
[profile local]
region = ap-northeast-1
output = json
EOF
aws configure --profile=local
