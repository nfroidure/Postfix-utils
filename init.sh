#! /bin/sh

# Constants
CONF_PATH="../conf/";
MYSQL_PATH="../mysql/";

# Config
set -- $($(dirname $0)/${MYSQL_PATH}credentials.sh);
dbusername=$1;
dbpassword=$2;

echo "Installing Postfix packages"
aptitude install postfix postfix-mysql
echo "Remove Exim (installed by default)"
apt-get --purge remove 'exim4*'
echo "Adding POP IMAP services (Dovecot)"
apt-get install dovecot-pop3d dovecot-imapd dovecot-mysql
echo "A simple mail reader"
apt-get install mutt
echo "Mail scan"
apt-get install amavisd-new spamassassin clamav-daemon lhasa arj unrar-nonfree zoo nomarch cpio lzop cabextract

$maildbname=$(cat "$(dirname $0)/${CONF_PATH}maildb");
if [ "$maildbname" != "" ]; then
	echo "Delete the old database ($maildbname) first ? (yes/no)";
	read deletefirst
	if [ "$deletefirst" = "yes" ]; then
		echo "Deleting database $maildbname...";
		mysql --user=${dbuser} --password=${dbpassword} --execute="DROP DATABASE IF EXISTS $maildbname";
	fi
fi

# Asking the mail server db infos
echo "Enter the mailserver db name";
read maildbname
echo "Enter the mailserver db username";
read maildbusername
echo "Enter the mailserver db password for : $maildbusername";
stty -echo
read maildbpassword
stty echo

echo "Create the given user ? (yes/no)";
read createuser
if [ "$createuser" = "yes" ]; then
	echo "Creating the mail db user...";
	$(dirname $0)/${MYSQL_PATH}createuser.sh $maildbusername $maildbpassword $dbusername $dbpassword;
fi

echo "Creating the database";
mysql --user=${dbuser} --password=${dbpassword} --execute="CREATE DATABASE IF NOT EXISTS $maildbname";
echo "Giving right to user on the database";
mysql --user=${dbuser} --password=${dbpassword} --execute="GRANT SELECT ON $maildbname . * TO '$maildbusername'@'localhost'";
echo $maildbname > ${CONF_PATH}maildb;

echo "Creating virtualdomains table"
	mysql --user=${dbuser} --password=${dbpassword} --execute="
		USE $maildbname;
		CREATE TABLE \`virtualDomains\` (
			\`id\` int(11) NOT NULL auto_increment,
			\`name\` varchar(80) NOT NULL,
			PRIMARY KEY (\`id\`),
			UNIQUE KEY \`name\` (\`name\`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8;
	";

echo "Setting virtualdomains config"
echo "user = $maildbusername
password = $maildbpassword
hosts = 127.0.0.1
dbname = $maildbname
query = SELECT 1 FROM virtualDomains WHERE name='%s'
" >> /etc/postfix/mysql-virtual-mailbox-domains.cf

postconf -e virtual_mailbox_domains=mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf

echo "Creating virtualusers table"
	mysql --user=${dbuser} --password=${dbpassword} --execute="
		USE $maildbname;
		CREATE TABLE \`virtualUsers\` (
			\`id\` int(11) NOT NULL auto_increment,
			\`domain_id\` int(11) NOT NULL,
			\`password\` varchar(32) NOT NULL,
			\`email\` varchar(100) NOT NULL,
			PRIMARY KEY (\`id\`),
			UNIQUE KEY \`email\` (\`email\`),
			FOREIGN KEY (virtualDomain) REFERENCES virtualDomains(id) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8;
	";

echo "Setting virtualusers config"
echo "user = $maildbusername
password = $maildbpassword
hosts = 127.0.0.1
dbname = $maildbname
query = SELECT 1 FROM virtualUsers WHERE email='%s'
" >> /etc/postfix/mysql-virtual-mailbox-maps.cf

postconf -e virtual_mailbox_maps=mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf

echo "Creating virtualaliases table"
	mysql --user=${dbuser} --password=${dbpassword} --execute="
		USE $maildbname;
		CREATE TABLE \`virtualAliases\` (
			\`id\` int(11) NOT NULL auto_increment,
			\`virtualDomain\` int(11) NOT NULL,
			\`source\` varchar(100) NOT NULL,
			\`destination\` varchar(100) NOT NULL,
			PRIMARY KEY (\`id\`),
			FOREIGN KEY (virtualDomain) REFERENCES virtualDomains(id) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8;
	";

echo "Setting virtual aliases config"
echo "user = $maildbusername
password = $maildbpassword
hosts = 127.0.0.1
dbname = $maildbname
query = SELECT destination FROM virtualAliases WHERE source='%s'
" >> /etc/postfix/mysql-virtual-alias-maps.cf

echo "Setting virtual users config"
echo "user = $maildbusername
password = $maildbpassword
hosts = 127.0.0.1
dbname = $maildbname
query = SELECT email FROM virtualUsers WHERE email='%s'
" >> /etc/postfix/mysql-email2email.cf

postconf -e virtual_alias_maps=mysql:/etc/postfix/mysql-virtual-alias-maps.cf,mysql:/etc/postfix/mysql-email2email.cf

echo "Creating default domain"
$(dirname $0)/adddomain.sh elitwork elitwork.com yes

chgrp postfix /etc/postfix/mysql-*.cf
chmod u=rw,g=r,o= /etc/postfix/mysql-*.cf


echo "Setting up Dovecot"

groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/vmail -m
chown -R vmail:vmail /var/vmail
chmod u+w /var/vmail


echo "
protocols = imap imaps pop3 pop3s
disable_plaintext_auth = no
mail_location = maildir:/var/vmail/%d/%n/Maildir
namespace private {
    separator = .
    inbox = yes
}
mechanisms = plain login
passdb sql {
    args = /etc/dovecot/dovecot-vmail.conf.ext
}
userdb static {
    args = uid=5000 gid=5000 home=/var/vmail/%d/%n allow_all_users=yes
}
socket listen {
    master {
        path = /var/run/dovecot/auth-master
        mode = 0600
        user = vmail
    }

    client {
        path = /var/spool/postfix/private/auth
        mode = 0660
        user = postfix
        group = postfix
    }
}
protocol lda {
    auth_socket_path = /var/run/dovecot/auth-master
    postmaster_address = postmaster@elitwork.com
    mail_plugins = sieve
    log_path = /var/log/mail.log
}
" > /etc/dovecot/conf.d/90-custom.conf

echo "Setting Auth system to MySQL"
echo "
!include dovecot-vmail.conf.ext
" > /etc/dovecot/conf.d/10-auth.conf
echo "
	driver=mysql
	connect = host=127.0.0.1 dbname=$maildbname user=$maildbusername password=$maildbpassword
	default_pass_scheme = PLAIN-MD5
	password_query = \\
		SELECT email as user, password \\
		FROM virtualUsers WHERE email='%u';
	user_query = \\
		SELECT uid, 1000 as gid, CONCAT('/home/',user,'/%d/%n') AS home \\
		FROM virtualUsers \\
		JOIN virtualDomains ON virtualDomains.id=virtualUsers.virtualDomain \\
		WHERE email='%u';
" > /etc/dovecot/dovecot-sql.conf.ext


echo "Postfix to dovecot link"
echo "dovecot   unix  -       n       n       -       -       pipe
    flags=DRhu chroot= user=elitwork:www-users argv=/usr/lib/dovecot/deliver -f \${sender} -d \${recipient}" >> /etc/postfix/master.cf

postconf -e virtual_transport=dovecot
postconf -e dovecot_destination_recipient_limit=1

echo "Setting log rotation"
echo "/var/log/dovecot-deliver.log {
        weekly
        rotate 14
        compress
}" >> /etc/logrotate.d/dovecot-deliver

echo "Setting dovecot rights"
chgrp vmail /etc/dovecot/dovecot.conf
chmod g+r /etc/dovecot/dovecot.conf

# For local postconf -e "mynetworks=192.168.1.0/24 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
postconf -e "mynetworks=192.168.1.0/24 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
postconf -e smtpd_sasl_type=dovecot
postconf -e smtpd_sasl_path=private/auth
postconf -e smtpd_sasl_auth_enable=yes
postconf -e "smtpd_recipient_restrictions=permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination"

#smtp-amavis unix -      -       n     -       2  smtp
#    -o smtp_data_done_timeout=1200
#    -o smtp_send_xforward_command=yes
#    -o disable_dns_lookups=yes
#    -o max_use=20

#127.0.0.1:10025 inet n  -       -     -       -  smtpd
#    -o content_filter=
#    -o local_recipient_maps=
#    -o relay_recipient_maps=
#    -o smtpd_restriction_classes=
#    -o smtpd_delay_reject=no
#    -o smtpd_client_restrictions=permit_mynetworks,reject
#    -o smtpd_helo_restrictions=
#    -o smtpd_sender_restrictions=
#    -o smtpd_recipient_restrictions=permit_mynetworks,reject
#    -o smtpd_data_restrictions=reject_unauth_pipelining
#    -o smtpd_end_of_data_restrictions=
#    -o mynetworks=127.0.0.0/8
#    -o smtpd_error_sleep_time=0
#    -o smtpd_soft_error_limit=1001
#    -o smtpd_hard_error_limit=1000
#    -o smtpd_client_connection_count_limit=0
#    -o smtpd_client_connection_rate_limit=0
#    -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks
#    -o local_header_rewrite_clients=

echo "Allowing SMTP authetification"

postconf -e smtpd_sasl_type=dovecot
postconf -e smtpd_sasl_path=private/auth
postconf -e smtpd_sasl_auth_enable=yes
postconf -e smtpd_recipient_restrictions=" \
  permit_mynetworks \
  permit_sasl_authenticated \
  reject_unauth_destination"


read -p "Reload postfix config ? (yes|no) : " answer
if [ "$answer" = "yes" ]; then
	echo "$sitedomain : Reloading Postfix configuration"
	/etc/init.d/postfix reload
fi

