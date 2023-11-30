#!/bin/bash

# Creates the RDS instance containing MSSQL DB
# accepts as args $1 the EC2ID and $2 the security group ID

# getting availability zone for ec2 --> rds
AZ=$(aws ec2 describe-instances \
    --instance-ids $1 \
    --query 'Reservations[].Instances[].Placement.AvailabilityZone' \
    --output text)

# creating mssql instance
# the --no-publicly-accessible flag allows only traffic from within VPC
aws rds create-db-instance \
    --db-instance-identifier mssql-server \
    --db-instance-class db.t3.small \
    --engine sqlserver-ex \
    --master-username admin \
    --vpc-security-group-ids $2 \
    --availability-zone $AZ \
    --no-publicly-accessible \
    --master-user-password vault123 \
    --allocated-storage 20 \
    --no-cli-pager

echo "waiting for db to become available, will take a few minutes..."
aws rds wait db-instance-available \
    --db-instance-identifier mssql-server

RDSEP=$(aws rds describe-db-instances \
    --db-instance-identifier mssql-server \
    --query "DBInstances[0].Endpoint.Address" \
    --no-cli-pager \
    --output text)