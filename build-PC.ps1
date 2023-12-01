Write-Host "Please login to doormat CLI before running this script." 

# setting IMAGE_ID to the AMI ID of the latest Amazon Linux 2 AMI, and SGID to security group just created
. .\configAWS.ps1

# Run EC2 instance
$EC2ID = aws ec2 run-instances `
    --image-id $IMAGE_ID `
    --instance-type t2.micro `
    --key-name vault-mssql-kp `
    --security-group-ids $SGID `
    --iam-instance-profile Name=vaultEC2 `
    --user-data file://build.sh `
    --query "Instances[0].InstanceId" `
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vault-mssql-ec2}]' `
    --no-paginate `
    --output text

# Retrieve the public DNS of the instance
$DNS = aws ec2 describe-instances `
    --instance-ids $EC2ID `
    --query 'Reservations[0].Instances[0].PublicDnsName' `
    --output text

# Output the SSH connection command
Write-Host "The EC2 instance is now running.  You can connect via SSH client with the generated key.pem file "
Write-Host "and the public EC2 DNS: $DNS"
Write-Host "RDS instance creation is now in progress.  Environment will be ready in about 5 minutes."
Write-Host "once logged in, run 'sql-get-users' to see the users and their logins in the COOLDB database like so: "
Write-Host "sql-get-users"
Write-Host "can also run custom queries using the built-in alias 'sql' like so: "
Write-Host 'sql "SELECT name FROM sys.databases;"'
Write-Host "Run cleanup.sh to delete all resources created by this script."