## Vault AWS MSSQL Lab

### Abstract
Spin up a MSSQL RDS instance, as well as a single ec2 Vault node that also acts as a MSSQL server to the RDS.  

### Discussion
build.sh -- orchestrates all other scripts together, taking into acct pc and mac/linux users

build.sh calls in this order:
bootstrapInstance.sh -- creates ec2 instance and security groups, deploys tiny vault server, and installs sql cmd tools; exports instance ID and PEM

bootstrapRDS.sh -- creates RDS instance, exports RDS endpoint

configureMSSQL -- configures mssql db through ec2, sets up mssql secrets engine

