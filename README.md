This shell scripts are designed to allow to install and manage a Postfix server
 close to automatically on a Debian Wheezy system. It is distributed under
 GNU/GPL v2 licence so use it at you own risks.
 
Those scripts are adapted to Wheezy from the great [ISPMail Postfix tutorial](https://workaround.org/ispmail/).

MySQL connection are based on my [MySQL-utils](https://github.com/nfroidure/MysqlUtils) repository.

# Config
Set the config/mysql folder path in the *.sh files. And run/adapt init.sh contents progressively.

# Scripts
init.sh : Install the postfix configuration (DO NOT USE AS IT)
adddomain.sh : Add a domain to the virtual domains table and create default accounts
addalias.sh : Add an alias to virtual aliases table
addmail.sh : Add a mail account

# Modify
If you improve those scripts, please, pull your commits !
