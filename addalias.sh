#! /bin/sh
# Copyright 2012 Elitwork
# Distributed under the terms of the GNU General Public License v2

# Constants
CONF_PATH="../conf/";
MYSQL_PATH="../mysql/";

# Params
domain=$1
destination=$2
pattern=$3

# Helps
if [ "$domain" = "" ] || [ "$destination" = "" ] || [ "$pattern" = "" ]; then
	echo "$(basename $0) 1:domain 2:destination 3:pattern"
	exit
fi

# Config
set -- $($(dirname $0)/${MYSQL_PATH}credentials.sh);
dbusername=$1;
dbpassword=$2;
maildbname=$(cat "$(dirname $0)/${CONF_PATH}maildb");

virtualdomainid=$(mysql --batch --raw --silent --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	SELECT id FROM virtualDomains ORDER BY id DESC LIMIT 1");
echo "Virtual domain id is : $virtualdomainid"

echo "Adding alias $pattern@$domain to $destination"
mysql --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	INSERT INTO virtualAliases (virtualDomain, source, destination)
	VALUES ($virtualdomainid, '$pattern@$domain', '$destination');
";

#echo "Testing config" // Should ask a sample domain to allow testing
#postmap -q "$username@$domain" mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
#postmap -q "$username@$domain" mysql:/etc/postfix/mysql-virtual-alias-maps.cf
#postmap -q "$username@$domain" mysql:/etc/postfix/mysql-email2email.cf

