#! /bin/sh
# Copyright 2012 Elitwork
# Distributed under the terms of the GNU General Public License v2

# Constants
CONF_PATH="../conf/";
MYSQL_PATH="../mysql/";

# Params
username=$1
domain=$2
if [ "$3" != "no" ]; then
	save="yes";
fi

# Helps
if [ "$username" = "" ] || [ "$domain" = "" ]; then
	echo "$(basename $0) 1:username 2:domain 3:save(yes|no)"
	exit
fi

# Config
set -- $($(dirname $0)/${MYSQL_PATH}credentials.sh);
dbusername=$1;
dbpassword=$2;
maildbname=$(cat "$(dirname $0)/${CONF_PATH}maildb");

if [ "$save" = "yes" ]; then
	echo "$domain : Saving domain in maildomains.db"
	echo "$username $domain" >> "$(dirname $0)/${CONF_PATH}maildomains.db"
fi

echo "Adding virtual domain..."
mysql --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	INSERT INTO virtualDomains (name,uid,user) VALUES ('$domain',$(id -u $username),'$username');";

virtualdomainid=$(mysql --batch --raw --silent --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	SELECT id FROM virtualDomains ORDER BY id DESC LIMIT 1");
echo "Virtual domain id is : $virtualdomainid"

read -p "Create a postmaster ? (yes|no) : " answer
if [ "$answer" = "yes" ]; then
	read -p "Give the postmaster password : " password
	echo "Creating postmaster"
	mysql --user=${dbuser} --password=${dbpassword} --execute="
		USE $maildbname;
		INSERT INTO virtualUsers (virtualDomain, email, password)
			VALUES ($virtualdomainid, 'postmaster@$domain', MD5('$password'));";
else
	echo "Redirecting to default postmaster"
	mysql --user=${dbuser} --password=${dbpassword} --execute="
		USE $maildbname;
		INSERT INTO virtualAliases (virtualDomain, source, destination)
		VALUES ($virtualdomainid, 'postmaster@$domain', 'postmaster@elitwork.com');
	";
fi

echo "Redirecting abuse+webmaster to default postmaster"
mysql --user=${dbuser} --password=${dbpassword} --execute="
	USE $maildbname;
	INSERT INTO virtualAliases (virtualDomain, source, destination)
	VALUES ($virtualdomainid, 'abuse@$domain', 'postmaster@elitwork.com'),
		   ($virtualdomainid, 'webmaster@$domain', 'postmaster@elitwork.com');
";

echo "Creating reception directory"
mkdir /home/$username/$domain
chown $username:www-users /home/$username/$domain
chmod 775 /home/$username/$domain

echo "Testing config"
postmap -q "postmaster@$domain" mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
postmap -q "postmaster@$domain" mysql:/etc/postfix/mysql-virtual-alias-maps.cf
postmap -q "postmaster@$domain" mysql:/etc/postfix/mysql-email2email.cf

