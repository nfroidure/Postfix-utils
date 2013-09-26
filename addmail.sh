#! /bin/sh
# Copyright 2012 Elitwork
# Distributed under the terms of the GNU General Public License v2

# Constants
CONF_PATH="../conf/";
MYSQL_PATH="../mysql/";

# Params
domain=$1
username=$2

# Helps
if [ "$username" = "" ] || [ "$domain" = "" ]; then
	echo "$(basename $0) 1:domain 2:username"
	exit
fi

# Config
set -- $($(dirname $0)/${MYSQL_PATH}credentials.sh);
dbusername=$1;
dbpassword=$2;
maildbname=$(cat "$(dirname $0)/${CONF_PATH}maildb");

virtualdomainid=$(mysql --batch --raw --silent --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	SELECT id FROM virtualDomains WHERE name='$domain'");
echo "Virtual domain id is : $virtualdomainid"

read -p "Give $username@$domain password : " password
echo "Creating postmaster"
mysql --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	INSERT INTO virtualUsers (virtualDomain, email, password)
	VALUES ($virtualdomainid, '$username@$domain', MD5('$password'));";

echo "Testing config"
postmap -q "$username@$domain" mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
postmap -q "$username@$domain" mysql:/etc/postfix/mysql-virtual-alias-maps.cf
postmap -q "$username@$domain" mysql:/etc/postfix/mysql-email2email.cf

