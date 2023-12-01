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

# create role using this policy
aws iam create-role \
    --role-name describeInstance \
    --assume-role-policy-document "$TRUST_POLICY" \
    --no-cli-pager

# Attach the AmazonEC2ReadOnlyAccess policy to the IAM role
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess \
    --role-name describeInstance

# Create an IAM instance profile and associate it with the IAM role
aws iam create-instance-profile --instance-profile-name vaultEC2 --no-cli-pager

# Associate the IAM role with the IAM instance profile
aws iam add-role-to-instance-profile --role-name describeInstance --instance-profile-name vaultEC2

VPCID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)

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
    --cidr 0.0.0.0/0

# allow all outgoing traffic on port 1433
aws ec2 authorize-security-group-egress \
    --group-id $SGID --protocol tcp \
    --port 1433 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SGID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SGID \
    --protocol tcp \
    --port 8200 \
    --cidr 0.0.0.0/0

aws ec2 create-key-pair \
    --key-name vault-mssql-kp \
    --key-type rsa \
    --key-format pem \
    --query "KeyMaterial" \
    --output text >key.pem

chmod 400 key.pem 

sleep 10
