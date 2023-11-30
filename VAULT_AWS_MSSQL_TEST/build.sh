#!/bin/bash

# my mac takes 858 seconds, or 14.3 minutes to complete this script
# if using PC, must authenticate seperately and remove below line before running

# Asking if using a PC
read -p "Is this shell operating in a Unix-based OS? (yes/no): " answer

# Converting to lowercase
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

OS=true

# Check if the answer is "yes" and run the script if true
if [[ "$answer" == "yes" || "$answer" == "y" ]]; then
	echo "Relax while infra is created."
	doormat login && eval $(doormat aws export --role $(doormat aws list | tail -n 1 | cut -b 2-))

	echo "creating a Vault single-server EC2 instance"
	. configAWS.sh
	. bootstrapInstance.sh $SGID

	echo "done creating EC2 instance, security group, and key pair"

	echo "starting creation of MSSQL RDS instance"
	. bootstrapRDS.sh $EC2ID $SGID

	echo "done creating RDS instance"

	echo "configuring DB from within EC2"
	. configDB.sh $RDSEP $OS $DNS

	echo "configuring MSSQL secrets engine in Vault EC2"
	. configEngine.sh $RDSEP $DNS

	echo "RDS EP: "$RDSEP
	echo "EC2 DNS" $DNS
	echo "ssh -o StrictHostKeyChecking=no -i key.pem ec2-user@$DNS"

	echo "Environment ready! You can now run sql queries from ec2 using alias 'sql', like so: "
	echo 'sql "SELECT name FROM sys.databases"'

else
	OS=false
	if ! doormat login -v 2>/dev/null; then
		echo
		echo "Please authenticate to doormat CLI and re-run this script."
		exit 1
	fi

	echo "For Windows machine, user must manually run configDBwindows.sh from inside EC2"
	echo "using RDS endpoint output after rds creation"

	. configAWS.sh

	. bootstrapInstance.sh $SGID

	. bootstrapRDS.sh $EC2ID $SGID


	echo "Everything complete except DB config! User must now run "
	echo "configDBwindows.sh inside the now ready EC2 instance."
	echo "Script uses RDS endpoint as arguement.  Here is the command: "
	echo "sudo chmod +x configDB.sh; ./configDB.sh $RDSEP $OS"
fi
