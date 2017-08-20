#!/bin/bash
#
# Copyright (C) 2017 - Dorance Martinez C. 
# Author: Dorance Martinez - dorancemc@gmail.com
# SPDX-License-Identifier: Apache-2.0
#
# Descripcion: Script para instalar rundeck en un server Centos 7.0
#
# Version: 0.1.0 - 04-mar-2017
#

#define
HOSTNAME=`hostname`
country=CO
state=ValleDelCauca
locality=Cali
organization=local
organizationalunit=automatizacion
servername=${HOSTNAME}
email="server@${HOSTNAME}"
mysql_root=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12)
myrundeck_user="rund3ck"
myrundeck_passwd=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12)
myrundeck_db="rundeck"

linux_variant() {
  if [ -f "/etc/redhat-release" ]; then
    distro="rh"
    flavour=$(cat /etc/redhat-release | cut -d" " -f1 | tr '[:upper:]' '[:lower:]' )
    version=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1 )
  else
    distro="unknown"
  fi
}

command_exists () {
    type "$1" &> /dev/null ;
}

unknown() {
  echo "distro no reconocida por este script :( "
  exit 1
}

install_rundeck() {
  #install
  rpm -Uvh http://repo.rundeck.org/latest.rpm &&
  rpm -Uvh http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm &&
  yum install java-1.8.0-openjdk -y &&
  yum install rundeck -y &&
  yum install epel-release -y &&
  yum install nginx -y &&
  yum install mysql-server -y &&
  return 0
}

configure_rundeck() {
  # security/firewall rules
  firewall-cmd --zone=public --permanent --add-port=4440/tcp &&
  firewall-cmd --permanent --zone=public --add-service=http &&
  firewall-cmd --permanent --zone=public --add-service=https &&
  firewall-cmd --reload &&
  setsebool -P httpd_can_network_connect true &&
  # start services
  systemctl start rundeckd &&
  systemctl start nginx &&
  systemctl start mysqld &&
  #configure rundeck
  sed -i "s/localhost/${HOSTNAME}/g" /etc/rundeck/framework.properties &&
  sed -i "s/localhost:4440/${HOSTNAME}/g" /etc/rundeck/rundeck-config.properties &&
  #configure nginx
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/${HOSTNAME}.key -out /etc/nginx/${HOSTNAME}.crt -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$servername/emailAddress=$email" &&
  sed -i '/listen       80 default_server/a \
          return 301 https://$host$request_uri;' /etc/nginx/nginx.conf &&
  cd /etc/nginx/conf.d &&
cat <<EOF >rundeck.conf
server {
    listen 80;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443;
    server_name ${HOSTNAME};
    ssl_certificate           ${HOSTNAME}.crt;
    ssl_certificate_key       ${HOSTNAME}.key;
    ssl on;
    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;
    access_log            /var/log/nginx/rundeck.access.log;
    location / {
      proxy_set_header        Host \$host;
      proxy_set_header        X-Real-IP \$remote_addr;
      proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header        X-Forwarded-Proto \$scheme;
      # Fix the “It appears that your reverse proxy set up is broken" error.
      proxy_pass          http://${HOSTNAME}:4440;
      proxy_read_timeout  90;
      proxy_redirect      http://${HOSTNAME}:4440 https://${HOSTNAME};
    }
  }
EOF
ls rundeck.conf &&
  #configure mysql
cat <<EOF >rundeck.sql
UPDATE mysql.user SET Password=PASSWORD('${mysql_root}') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
CREATE DATABASE ${myrundeck_db};
GRANT ALL ON ${myrundeck_db}.* to '${myrundeck_user}'@'localhost' identified by '${myrundeck_passwd}';
flush privileges;
EOF
  mysql -u root <rundeck.sql &&
  #configure rundeck mysql
  sed -i 's/dataSource.url/#dataSource.url/g' /etc/rundeck/rundeck-config.properties &&
cat <<EOF >>/etc/rundeck/rundeck-config.properties
# MySQL Configure
dataSource.url = jdbc:mysql://localhost/rundeck?autoReconnect=true
dataSource.username = ${myrundeck_user}
dataSource.password = ${myrundeck_passwd}
dataSource.driverClassName=com.mysql.jdbc.Driver
# Enables DB for Project configuration storage
rundeck.projectsStorageType=db
# Encryption for project config storage
rundeck.config.storage.converter.1.type=jasypt-encryption
rundeck.config.storage.converter.1.path=projects
rundeck.config.storage.converter.1.config.password=mysecr3t
# Enable DB for Key Storage
rundeck.storage.provider.1.type=db
rundeck.storage.provider.1.path=keys
# Encryption for Key Storage
rundeck.storage.converter.1.type=jasypt-encryption
rundeck.storage.converter.1.path=keys
rundeck.storage.converter.1.config.password=mysecr3t
EOF
cat <<EOF >>.carcelero
mysql_root_passwd=${mysql_root}
EOF
  #restart services
  systemctl restart nginx &&
  systemctl restart rundeckd &&
  return 0
}

run_core() {
  linux_variant
  if [ "$distro" == "rh" ] && [ $version -ge 7 ]; then
      install_rundeck &&
      configure_rundeck &&
      echo -e "ejecute tail -f /var/log/rundeck/service.log \ny espere una salida similar a: \n"
      echo "2017-03-04 00:19:07.535:INFO:oejs.ServerConnector:main: Started ServerConnector@1a916120{HTTP/1.1}{0.0.0.0:4440}"
      echo -e "\ningrese por http://${HOSTNAME}"
  else
    unknown
  fi
  return 0
}

run_core &&
exit 0
