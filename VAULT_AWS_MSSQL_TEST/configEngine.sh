#!/bin/bash
root=$(ssh -o StrictHostKeyChecking=no -i key.pem ec2-user@$2 "cat root")
# enable database secrets engine
curl -X POST \
    -H "X-Vault-Token: $root" \
    -d '{"type":"database"}' \
    http://$2:8200/v1/sys/mounts/database

# create mssql config
curl -X PUT \
    -H "X-Vault-Token: $root" \
    -d '{
        "allowed_roles":"vault-admin-role",
        "connection_url":"sqlserver://{{username}}:{{password}}@'$1'",
        "password":"pw",
        "plugin_name":"mssql-database-plugin",
        "username":"vault_admin"
    }' \
    http://$2:8200/v1/database/config/mssql

# create role
curl -X PUT -H "X-Vault-Request: true" \
    -H "X-Vault-Token: $root" \
    --data @- \
    http://$2:8200/v1/database/roles/vault-admin-role <<EOF
{
    "db_name": "mssql",
    "default_ttl": "1h",
    "max_ttl": "24h",
    "creation_statements": [
        "USE COOLDB;",
        "CREATE LOGIN [{{name}}] WITH PASSWORD = '{{password}}';",
        "CREATE USER [{{name}}] FOR LOGIN [{{name}}];",
        "GRANT SELECT, EXECUTE, ALTER ON SCHEMA::dbo TO [{{name}}];"
    ]
}
EOF