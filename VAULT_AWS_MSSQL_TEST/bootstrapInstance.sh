#!/bin/bash

# creates a single vault server to control the mssql db

SINGLE_SERVER=$(cat << 'EOF'
#!/bin/bash
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum-config-manager --add-repo https://packages.microsoft.com/config/rhel/7/prod.repo
yum update -y
yum -y install vault-enterprise< "/dev/null"
mkdir -p /mnt/vault/data
chown -R vault /mnt/vault

echo "PASTE_VAULT_LICENSE" > /etc/vault.d/vault.hclic 

cat <<EOF1 > /etc/vault.d/vault.hcl
storage "file" {
  path    = "/mnt/vault/data"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_disable     = true
}

license_path = "/etc/vault.d/vault.hclic"
api_addr = "http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8200"
EOF1
echo 'export VAULT_ADDR=http://127.0.0.1:8200' >> /etc/environment
systemctl start vault
sudo vault operator init -key-shares=1 -key-threshold=1 > /home/ec2-user/keys
sudo vault operator unseal $(grep 'Key 1:' /home/ec2-user/keys | awk '{print $NF}')
echo $(grep 'Key 1:' /home/ec2-user/keys | awk '{print $NF}') > /home/ec2-user/unseal
echo $(grep 'Initial Root Token:' /home/ec2-user/keys | awk '{print $NF}') > /home/ec2-user/root
rm /home/ec2-user/keys
EOF
)

IMAGE_ID=$(aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query 'Parameters[0].[Value]' \
    --output text)

EC2ID=$(aws ec2 run-instances \
    --image-id $IMAGE_ID \
    --instance-type t2.micro \
    --key-name vault-mssql-kp \
    --security-group-ids $1 \
    --iam-instance-profile Name=vaultEC2 \
    --user-data "$SINGLE_SERVER" \
    --query "Instances[0].InstanceId" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vault-mssql-ec2}]' \
    --no-cli-pager \
    --output text)

# wait for instance to be created
aws ec2 wait instance-running \
    --instance-ids $EC2ID

DNS=$(aws ec2 describe-instances \
    --instance-ids $EC2ID \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text)

echo "ssh -o StrictHostKeyChecking=no -i key.pem ec2-user@$DNS"
