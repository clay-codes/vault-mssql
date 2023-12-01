Write-Host "Please login to doormat/AWS CLI before running this script." 

# PowerShell version of the provided Bash script

# Assuming doormat commands are handled separately as they are environment-specific
# doormat login
# Evaluating doormat aws export might need a different approach in PowerShell

# Get EC2 Instance ID
$ec2ID = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=vault-mssql-ec2" "Name=instance-state-name,Values=running" `
    --query "Reservations[].Instances[].InstanceId" `
    --output text

# Terminate EC2 instance
aws ec2 terminate-instances --instance-ids $ec2ID

# Delete key pair
aws ec2 delete-key-pair --key-name vault-mssql-kp

# Delete all created files
Remove-Item -Path key.pem, keys, root, unseal -Force -ErrorAction SilentlyContinue

# Detach IAM role policy
aws iam detach-role-policy `
    --role-name ec2-mssql `
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess

# Get the ARN of the RDS policy
$RDSARN = aws iam list-policies --query 'Policies[?PolicyName==`RDS-policy`].Arn' --output text

# Detach and delete the IAM policy
aws iam detach-role-policy --role-name ec2-mssql --policy-arn $RDSARN
aws iam delete-policy --policy-arn $RDSARN

# Remove role from instance profile and delete IAM role and instance profile
aws iam remove-role-from-instance-profile `
    --instance-profile-name vaultEC2 `
    --role-name ec2-mssql

aws iam delete-role --role-name ec2-mssql
aws iam delete-instance-profile --instance-profile-name vaultEC2

# Delete RDS instance
aws rds delete-db-instance `
    --db-instance-identifier mssql-server `
    --skip-final-snapshot `
    --delete-automated-backups `
    --no-cli-pager

# Wait for RDS instance deletion
do {
    try {
        aws rds describe-db-instances --db-instance-identifier mssql-server | Out-Null
        Write-Host "Waiting for DB instance to be deleted..."
        Start-Sleep -Seconds 10
    } catch {
        Write-Host "DB instance has been deleted."
        break
    }
} while ($true)

# Delete security group (must be after DB and EC2 deletion due to dependency)
aws ec2 delete-security-group --group-name vault-mssql-sg
