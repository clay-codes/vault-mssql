#!/bin/bash
# installs dependencies for vault and mssql tools
function install_deps {
    yum install -y yum-utils
    yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    yum-config-manager --add-repo https://packages.microsoft.com/config/rhel/7/prod.repo
    yum -y install vault-enterprise <"/dev/null"
    yum -y install jq <"/dev/null"
    yum update -y
    yum install awscli -y
    ACCEPT_EULA=Y yum install -y msodbcsql17
    ACCEPT_EULA=Y yum install -y mssql-tools
    yum install -y unixODBC-devel
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >>/home/ec2-user/.bashrc
    source /home/ec2-user/.bashrc
}

# initializes a single server vault instance with file storage BE
function init_vault {
    mkdir -p /mnt/vault/data
    chown -R vault /mnt/vault
    echo "" >/etc/vault.d/vault.hclic
    cat <<EOF1 >/etc/vault.d/vault.hcl
storage "file" {
  path    = "/mnt/vault/data"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_disable     = true
}

license_path = "/etc/vault.d/vault.hclic"
api_addr = "http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8200"
log_level = "debug"
EOF1
    echo 'export VAULT_ADDR=http://127.0.0.1:8200' >>/etc/environment
    echo 'export AWS_DEFAULT_REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')' >>/etc/environment
    export VAULT_ADDR=http://127.0.0.1:8200
    systemctl start vault
    vault operator init -key-shares=1 -key-threshold=1 >/home/ec2-user/keys
    echo $(grep 'Key 1:' /home/ec2-user/keys | awk '{print $NF}') >/home/ec2-user/unseal
    vault operator unseal $(cat home/ec2-user/unseal)
    echo $(grep 'Initial Root Token:' /home/ec2-user/keys | awk '{print $NF}') >/home/ec2-user/root
    rm /home/ec2-user/keys
}

# Creates the RDS instance containing MSSQL DB
# accepts as args $1 the EC2ID and $2 the security group ID
# the --no-publicly-accessible flag allows only traffic from within VPC
function bootstrapRDS {
    AZ=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
    echo "export AWS_DEFAULT_REGION=${AZ%?}" >>/etc/environment

    export AWS_DEFAULT_REGION=${AZ%?}

    SGID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=vault-mssql-ec2" "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].SecurityGroups[].GroupId" \
        --output text)

    aws rds create-db-instance \
        --db-instance-identifier mssql-server \
        --allocated-storage 20 \
        --db-instance-class db.t3.small \
        --engine sqlserver-ex \
        --master-username admin \
        --master-user-password vault123 \
        --vpc-security-group-ids $SGID \
        --availability-zone $AZ \
        --db-subnet-group-name vault-mssql-sng \
        --backup-retention-period 0 \
        --no-multi-az \
        --no-publicly-accessible \
        --no-paginate

    aws rds wait db-instance-available \
        --db-instance-identifier mssql-server

    export RDSEP=$(aws rds describe-db-instances \
        --db-instance-identifier mssql-server \
        --query "DBInstances[0].Endpoint.Address" \
        --output text)

    echo "export RDSEP=$RDSEP" >>/etc/environment
}

function configEC2-RDS {
    echo 'alias sql="sqlcmd -S $RDSEP -U admin -P vault123 -Q "$@""' >>/home/ec2-user/.bashrc
    cat <<EOF >>/home/ec2-user/.bashrc
function sql-get-users {
sql \
"USE COOLDB;
GO
SELECT
    dp.name AS DatabaseUserName,
    sp.name AS LoginName,
    dp.create_date
FROM
    sys.database_principals dp
LEFT JOIN
    sys.server_principals sp ON dp.sid = sp.sid
WHERE
    dp.type IN ('S')
    AND dp.name NOT IN ('dbo', 'guest', 'sys', 'INFORMATION_SCHEMA');"
}
EOF
    sqlcmd -S $RDSEP -U admin -P vault123 -Q \
    "USE master;
    GO
    CREATE LOGIN [vault_admin] WITH PASSWORD = 'pw';
    GRANT ALTER ANY LOGIN TO [vault_admin];
    CREATE DATABASE COOLDB;
    GO
    USE COOLDB;
    CREATE USER [vaultadmin] FOR LOGIN [vault_admin];
    EXEC sp_addrolemember db_owner, [vaultadmin];"
}

# configures Vault with MSSQL database secrets engine
function config_engine {
    vault login - </home/ec2-user/root
    vault secrets enable database
    
    # create config in vault
    vault write database/config/mssql \
        plugin_name=mssql-database-plugin \
        connection_url="sqlserver://{{username}}:{{password}}@$RDSEP" \
        allowed_roles="cooldb" \
        username="vault_admin" \
        password="pw"

    # Define SQL commands for user creation
    vault_admin_sql=$(cat <<EOF
USE COOLDB;
CREATE LOGIN [{{name}}] WITH PASSWORD = '{{password}}';
CREATE USER [{{name}}] FOR LOGIN [{{name}}];
GRANT SELECT, EXECUTE, ALTER ON SCHEMA::dbo TO [{{name}}];
EOF
)

    # Define SQL commands for revocation
    revocation_sql=$(cat <<EOF
USE COOLDB
IF EXISTS (SELECT name FROM sys.database_principals WHERE name = N'{{name}}')
BEGIN
    DROP USER [{{name}}]
END
IF EXISTS (SELECT name FROM master.sys.server_principals WHERE name = N'{{name}}')
BEGIN
    DROP LOGIN [{{name}}]
END
EOF
)

    vault write database/roles/cooldb \
        db_name=mssql \
        creation_statements="$vault_admin_sql" \
        revocation_statements="$revocation_sql" \
        default_ttl="1h" \
        max_ttl="24h"
}

install_deps
init_vault
bootstrapRDS
configEC2-RDS
config_engine