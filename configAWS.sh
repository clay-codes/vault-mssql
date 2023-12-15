#!/bin/bash

# creates instance profile, its role, and policy to allow
# self-lookup of api_addr upon creation.
#
# also creates a security group for rds and ec2, user can
# modify for finer-grained security

# create role policy to allow ec2 services to be described
TRUST_POLICY='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'

# allow ec2 to create, describe, and delete RDS instances, describe ec2 instances
RDS_POLICY='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:CreateDBInstance",
                "rds:DescribeDBInstances",
                "rds:DeleteDBInstance",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}'

# Create the IAM policy
RDSARN=$(aws iam create-policy \
    --policy-name RDS-policy \
    --policy-document "$RDS_POLICY" \
    --query 'Policy.Arn' \
    --output text)

# create role using this policy
aws iam create-role \
    --role-name ec2-mssql \
    --assume-role-policy-document "$TRUST_POLICY" >/dev/null
# Attach the AmazonEC2ReadOnlyAccess policy to the IAM role
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess \
    --role-name ec2-mssql >/dev/null

aws iam attach-role-policy \
    --policy-arn "$RDSARN" \
    --role-name ec2-mssql >/dev/null

# Create an IAM instance profile and associate it with the IAM role
aws iam create-instance-profile --instance-profile-name vaultEC2 >/dev/null

sleep 10

# Associate the IAM role with the IAM instance profile
aws iam add-role-to-instance-profile --role-name ec2-mssql --instance-profile-name vaultEC2

VPCID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[].VpcId' --output text)

[ -z "$VPCID" ] && echo "No default VPC found.  Must have default vpc and associated subnet with network connection to run" && exit 1

AZ=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[0].[AvailabilityZone]' --output text)
region=${AZ%?}

AZCH="${AZ: -1}"
# if last char is a, set char to b, else set char to a
[ "$AZCH" == "a" ] && char="b" || char="a"

# Get VPC CIDR block
cidr_block=$(aws ec2 describe-vpcs --vpc-ids $VPCID --query 'Vpcs[0].CidrBlock' --output text)

# Extract the first 5 digits
cidr=$(echo $cidr_block | awk -F. '{print $1"."$2"."$3}')

SNID1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query "Subnets[0].SubnetId" --output text)
# Create the second subnet
SNCIDR="$cidr.240/28"
SNAZ=$region$char
SNID2=$(aws ec2 create-subnet \
    --vpc-id $VPCID \
    --availability-zone $SNAZ \
    --cidr-block $SNCIDR \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=vault-mssql-sn}]" \
    --query 'Subnet.SubnetId' \
    --output text)

# Create the DB subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name vault-mssql-sng \
    --db-subnet-group-description "2 subnets for vault-mssql" \
    --subnet-ids "[\"$SNID1\",\"$SNID2\"]" >/dev/null

SGID=$(aws ec2 create-security-group \
    --group-name vault-mssql-sg \
    --description "allows traffic vault from-to  mssql" \
    --vpc-id $VPCID \
    --query 'GroupId' \
    --no-cli-pager \
    --output text)

# allow all incoming traffic on port 1433
aws ec2 authorize-security-group-ingress \
    --group-id $SGID \
    --protocol tcp \
    --port 1433 \
    --cidr 0.0.0.0/0 >/dev/null

# allow all outgoing traffic on port 1433
aws ec2 authorize-security-group-egress \
    --group-id $SGID --protocol tcp \
    --port 1433 \
    --cidr 0.0.0.0/0 >/dev/null

aws ec2 authorize-security-group-ingress \
    --group-id $SGID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 >/dev/null

aws ec2 authorize-security-group-ingress \
    --group-id $SGID \
    --protocol tcp \
    --port 8200 \
    --cidr 0.0.0.0/0 >/dev/null

aws ec2 create-key-pair \
    --key-name vault-mssql-kp \
    --key-type rsa \
    --key-format pem \
    --query "KeyMaterial" \
    --output text >key.pem

chmod 400 key.pem

IMAGE_ID=$(aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query 'Parameters[0].[Value]' \
    --output text)

echo "Done with AWS stuff."
