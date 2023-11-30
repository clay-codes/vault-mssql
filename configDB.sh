#!/bin/bash
configDB=$(cat << EOF 
sudo ACCEPT_EULA=Y yum install -y msodbcsql17
sudo ACCEPT_EULA=Y yum install -y mssql-tools
sudo yum install -y unixODBC-devel
echo 'export PATH="\$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
echo 'alias sql="sqlcmd -S $1 -U admin -P vault123 -Q "\$@""' | sudo tee /etc/profile.d/sql-alias.sh > /dev/null
sudo chmod +x /etc/profile.d/sql-alias.sh

$2 && vault login \$(cat root) || vault login $(cat root)

# create vault admin user in DB
sqlcmd -S $1 \
-U admin \
-P vault123 \
-Q \
"USE master;
CREATE LOGIN [vault_admin] WITH PASSWORD = 'pw';
GRANT ALTER ANY LOGIN TO [vault_admin];
CREATE DATABASE COOLDB;
go
USE COOLDB;
CREATE USER [vaultadmin] FOR LOGIN [vault_admin];
EXEC sp_addrolemember db_owner, [vaultadmin];"
EOF
)
# only evaluates true (exits 0) if A && B are true, so B must be evaluated
# if $2 is false, F && B is always false, thus F && will always exit zero before evaluating B
# if using mac/linux, ssh; else, eval
$2 && ssh -o StrictHostKeyChecking=no -i key.pem ec2-user@$3 "$configDB" || eval "$configDB" 

# conversley, if $2 is true, (T || B) is always true, thus T || will always exit zero before evaluating B
# F || T => T (exit zero); requires B to be evauluates, as expression could still be true if A = F
# if not using mac/linux, evaluate rest of expression
$2 || sudo chmod +x configEngine.sh && ./configEngine.sh $1 $3