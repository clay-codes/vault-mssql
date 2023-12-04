#!/bin/bash

doormat login && eval `doormat aws export --role $(doormat aws list | tail -n 1 | cut -b 2-)`

# get ec2ID
ec2ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=vault-mssql-ec2" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

# delete ec2
aws ec2 terminate-instances --instance-ids $ec2ID

# delete key pair
aws ec2 delete-key-pair --key-name vault-mssql-kp

# delete all created files
rm -f key.pem keys root unseal

# deleting IAM stuff
aws iam detach-role-policy \
    --role-name ec2-mssql \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess

RDSARN=$(aws iam list-policies --query 'Policies[?PolicyName==`RDS-policy`].Arn' --output text)

aws iam detach-role-policy --role-name ec2-mssql --policy-arn "$RDSARN"

aws iam delete-policy --policy-arn "$RDSARN"

aws iam remove-role-from-instance-profile \
    --instance-profile-name vaultEC2 \
    --role-name ec2-mssql

aws iam delete-role --role-name ec2-mssql

aws iam delete-instance-profile --instance-profile-name vaultEC2

# delete rds
aws rds delete-db-instance \
    --db-instance-identifier mssql-server \
    --skip-final-snapshot \
    --delete-automated-backups \
    --no-cli-pager

# wait for deletion
while aws rds describe-db-instances --db-instance-identifier mssql-server  >/dev/null 2>&1; do
    echo "Waiting for DB instance to be deleted..."
    sleep 10
done

echo "DB instance has been deleted."

# delete security group (must be after db and ec2 deletion due to dependancy)
aws ec2 delete-security-group --group-name vault-mssql-sg

# deleting subnets by their cidr block
subnet_id=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=172.31.255.208/28" --query 'Subnets[0].SubnetId' --output text)

aws ec2 delete-subnet --subnet-id $subnet_id
aws rds delete-db-subnet-group --db-subnet-group-name vault-mssql-sng