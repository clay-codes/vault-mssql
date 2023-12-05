#!/bin/bash
doormat login && eval `doormat aws export --role $(doormat aws list | tail -n 1 | cut -b 2-)`

. configAWS.sh

EC2ID=$(aws ec2 run-instances \
    --image-id $IMAGE_ID \
    --instance-type t2.micro \
    --key-name vault-mssql-kp \
    --security-group-ids $SGID \
    --subnet-id $SNID1 \
    --iam-instance-profile Name=vaultEC2 \
    --user-data file://bootstrap.sh \
    --query "Instances[0].InstanceId" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vault-mssql-ec2}]' \
    --no-paginate \
    --output text)

DNS=$(aws ec2 describe-instances \
    --instance-ids $EC2ID \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text)

echo "EC2 instance ready, but RDS will need an additional 10 minutes."
echo "ssh -o StrictHostKeyChecking=no -i key.pem ec2-user@$DNS"
echo "once logged in, run 'sql-get-users' to see the users and their logins in the COOLDB database."
echo "can also run custom queries using the built-in alias 'sql' like so: "
echo 'sql "SELECT name FROM sys.databases;"'
echo "Run cleanup.sh to delete all resources created by this script."