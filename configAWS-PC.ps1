# This is a PowerShell script equivalent to the provided Bash script

# Create role policy to allow ec2 services to be described
$TRUST_POLICY = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Principal = @{
                Service = "ec2.amazonaws.com"
            }
            Action = "sts:AssumeRole"
        }
    )
} | ConvertTo-Json -Compress

# Allow ec2 to create, describe, and delete RDS instances, describe ec2 instances
$RDS_POLICY = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Action = @("rds:CreateDBInstance", "rds:DescribeDBInstances", "rds:DeleteDBInstance", "ec2:ec2-mssqls")
            Resource = "*"
        }
    )
} | ConvertTo-Json -Compress

# Create the IAM policy
$RDSARN = aws iam create-policy `
    --policy-name RDS-policy `
    --policy-document $RDS_POLICY `
    --query 'Policy.Arn' `
    --output text

# Create role using this policy
aws iam create-role `
    --role-name ec2-mssql `
    --assume-role-policy-document $TRUST_POLICY | Out-Null

# Attach the AmazonEC2ReadOnlyAccess policy to the IAM role
aws iam attach-role-policy `
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess `
    --role-name ec2-mssql | Out-Null

aws iam attach-role-policy `
    --policy-arn $RDSARN `
    --role-name ec2-mssql | Out-Null

# Create an IAM instance profile and associate it with the IAM role
aws iam create-instance-profile --instance-profile-name vaultEC2 | Out-Null

Start-Sleep -Seconds 10

# Associate the IAM role with the IAM instance profile
aws iam add-role-to-instance-profile --role-name ec2-mssql --instance-profile-name vaultEC2

$VPCID = aws ec2 describe-vpcs `
    --filters "Name=isDefault,Values=true" `
    --query "Vpcs[0].VpcId" `
    --output text

$SGID = aws ec2 create-security-group `
    --group-name vault-mssql-sg `
    --description "allows traffic vault from-to mssql" `
    --vpc-id $VPCID `
    --query 'GroupId' `
    --no-cli-pager `
    --output text

# Allow all incoming traffic on port 1433
aws ec2 authorize-security-group-ingress `
    --group-id $SGID `
    --protocol tcp `
    --port 1433 `
    --cidr 0.0.0.0/0 | Out-Null

# Allow all outgoing traffic on port 1433
aws ec2 authorize-security-group-egress `
    --group-id $SGID `
    --protocol tcp `
    --port 1433 `
    --cidr 0.0.0.0/0 | Out-Null

aws ec2 authorize-security-group-ingress `
    --group-id $SGID `
    --protocol tcp `
    --port 22 `
    --cidr 0.0.0.0/0 | Out-Null

aws ec2 authorize-security-group-ingress `
    --group-id $SGID `
    --protocol tcp `
    --port 8200 `
    --cidr 0.0.0.0/0 | Out-Null

$keyMaterial = aws ec2 create-key-pair `
    --key-name vault-mssql-kp `
    --key-type rsa `
    --key-format pem `
    --query "KeyMaterial" `
    --output text

Set-Content -Path "key.pem" -Value $keyMaterial

# Set the key.pem file to read-only
Set-ItemProperty -Path "key.pem" -Name IsReadOnly -Value $true

$IMAGE_ID = aws ssm get-parameters `
    --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 `
    --query 'Parameters[0].[Value]' `
    --output text


Write-Host "Done with AWS stuff."
