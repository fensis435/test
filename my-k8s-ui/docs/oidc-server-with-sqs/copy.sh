mv -i /mnt/g/Downloads/oidc-*.zip .
chmod -x oidc-*.zip
scp oidc-*.zip vaio@192.168.0.36:~/oidc-server-with-sqs/
