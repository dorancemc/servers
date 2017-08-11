#!/bin/bash
#
# Copyright (C) 2017 - Dorance Martinez C
# Author: Dorance Martinez - dorancemc@gmail.com
# SPDX-License-Identifier: Apache-2.0
#
# Descripcion: Script para instalar radius y daloradius en un server Centos 7.0
#
# Version: 0.1.0 - 10-ago-2017
#

mysql_root=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12)
myradius_user="r4dius"
myradius_passwd=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12)
myradius_db="radius"

sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux
echo 0 > /sys/fs/selinux/enforce
yum install -y epel-release
yum install -y mariadb-server mariadb freeradius freeradius-mysql freeradius-utils wget unzip mod_ssl php-mysql php php-pear php-gd php-pear-DB

systemctl enable radiusd.service
systemctl enable httpd
systemctl enable mariadb
systemctl start httpd
systemctl start mariadb

#configure mysql
cat <<EOF >radius.sql
UPDATE mysql.user SET Password=PASSWORD('${mysql_root}') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
CREATE DATABASE ${myradius_db};
GRANT ALL ON ${myradius_db}.* to '${myradius_user}'@'localhost' identified by '${myradius_passwd}';
flush privileges;
EOF
mysql -u root <radius.sql

#configure radius
mysql -u ${myradius_user} -p"${myradius_passwd}" ${myradius_db} </etc/raddb/mods-config/sql/main/mysql/schema.sql
ln -s /etc/raddb/mods-available/sql /etc/raddb/mods-enabled/
sed -i 's/-sql/sql/g'  /etc/raddb/sites-enabled/default
grep  '#.*sql$' /etc/raddb/sites-enabled/default
sed -i 's/#.*sql$/\tsql/g' /etc/raddb/sites-enabled/default
sed -i "s/dialect = \"sqlite\"/\dialect = \"mysql\"/g" /etc/raddb/mods-available/sql
sed -i 's/#.*server =/\tserver =/g' /etc/raddb/mods-available/sql
sed -i 's/#.*port =/\tport =/g' /etc/raddb/mods-available/sql
sed -i "s/#.*login = \"radius\"/\tlogin = \"${myradius_user}\"/g" /etc/raddb/mods-available/sql
sed -i "s/#.*password = \"radpass\"/\tpassword = \"${myradius_passwd}\"/g" /etc/raddb/mods-available/sql
sed -i 's/#.*read_clients =/\tread_clients =/g' /etc/raddb/mods-available/sql

#configure daloradius
wget https://github.com/lirantal/daloradius/archive/master.zip
unzip master.zip
rm -rf master.zip
rmdir /var/www/html
mv daloradius-master /var/www/html
mysql -u ${myradius_user} -p"${myradius_passwd}" ${myradius_db} </var/www/html/contrib/db/fr2-mysql-daloradius-and-freeradius.sql
mysql -u ${myradius_user} -p"${myradius_passwd}" ${myradius_db} </var/www/html/contrib/db/mysql-daloradius.sql
sed -i "s/\$configValues\['CONFIG_DB_USER'\] = 'root'/\$configValues\['CONFIG_DB_USER'\] = '${myradius_user}'/g" /var/www/html/library/daloradius.conf.php
sed -i "s/\$configValues\['CONFIG_DB_PASS'\] = ''/\$configValues\['CONFIG_DB_PASS'\] = '${myradius_passwd}'/g" /var/www/html/library/daloradius.conf.php
chown -R apache: /var/www/html/

#restart services
systemctl restart radiusd.service
systemctl restart httpd

#firewall
firewall-cmd --zone=public --add-service=radius --permanent
firewall-cmd --zone=public --add-service=https --permanent
firewall-cmd --reload

#carcelero
cat <<EOF >>.carcelero
mysql_root_passwd=${mysql_root}
myradius_user=${myradius_user}
myradius_passwd=${myradius_passwd}
myradius_db=${myradius_db}
daloradius user = administrator
daloradius password = radius
EOF

cat .carcelero
