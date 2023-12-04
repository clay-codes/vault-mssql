# Define trust policy
$TRUST_POLICY = @"
{
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
}
"@

# Define RDS policy
$RDS_POLICY = @"
{
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
}
"@

# Create the IAM policy
$RDSARN = aws iam create-policy --policy-name RDS-policy --policy-document $RDS_POLICY --query 'Policy.Arn' --output text

# Create role using this policy
aws iam create-role --role-name ec2-mssql --assume-role-policy-document $TRUST_POLICY | Out-Null

# Attach the AmazonEC2ReadOnlyAccess policy to the IAM role
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess --role-name ec2-mssql | Out-Null
aws iam attach-role-policy --policy-arn $RDSARN --role-name ec2-mssql | Out-Null

# Create an IAM instance profile and associate it with the IAM role
aws iam create-instance-profile --instance-profile-name vaultEC2 | Out-Null

Start-Sleep -Seconds 10

# Associate the IAM role with the IAM instance profile
aws iam add-role-to-instance-profile --role-name ec2-mssql --instance-profile-name vaultEC2 | Out-Null

# Get VPC ID
$VPCID = aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text

# Determine availability zones
$AZ = aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text
$region = $AZ.Substring(0, $AZ.Length - 1)

# Get VPC CIDR block
$cidr_block = aws ec2 describe-vpcs --vpc-ids $VPCID --query 'Vpcs[0].CidrBlock' --output text
$cidr = $cidr_block.Substring(0, 6)

# Create the first subnet
$SNCB1 = "$($cidr).255.208/28"
$SNAZ1 = $region + "a"
$SNID1 = aws ec2 create-subnet --vpc-id $VPCID --availability-zone $SNAZ1 --cidr-block $SNCB1 --query 'Subnet.SubnetId' --output text

# Create the second subnet
$SNCB2 = "$($cidr).254.208/28"
$SNAZ2 = $region + "b"
$SNID2 = aws ec2 create-subnet --vpc-id $VPCID --availability-zone $SNAZ2 --cidr-block $SNCB2 --query 'Subnet.SubnetId' --output text

# Create the DB subnet group
aws rds create-db-subnet-group --db-subnet-group-name vault-mssql-sng --db-subnet-group-description "2 subnets for vault-mssql" --subnet-ids "[\"$SNID1\",\"$SNID2\"]" | Out-Null

# Create security group
$SGID = aws ec2 create-security-group --group-name vault-mssql-sg --description "allows traffic vault from-to mssql" --vpc-id $VPCID --query 'GroupId' --output text

# Configure security group rules
aws ec2 authorize-security-group-ingress --group-id $SGID --protocol tcp --port 1433 --cidr 0.0.0.0/0 | Out-Null
aws ec2 authorize-security-group-egress --group-id $SGID --protocol tcp --port 1433 --cidr 0.0.0.0/0 | Out-Null
aws ec2 authorize-security-group-ingress --group-id $SGID --protocol tcp --port 22 --cidr 0.0.0.0/0 | Out-Null
aws ec2 authorize-security-group-ingress --group-id $SGID --protocol tcp --port 8200 --cidr 0.0.0.0/0 | Out-Null

# Create key pair
$keyPair = aws ec2 create-key-pair --key-name vault-mssql-kp --query "KeyMaterial" --output text
$keyPair | Set-Content -Path "key.pem"

# Set key file permissions
Set-ItemProperty -Path "key.pem" -Name IsReadOnly -Value $true

# Get AMI ID
$IMAGE_ID = aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --output text

Write-Host "Done with AWS stuff."
