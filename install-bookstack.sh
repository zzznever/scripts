#!/bin/sh
# This script will install a new BookStack instance on a fresh Ubuntu 16.04 server.
# This script is experimental and does not ensure any security.

echo ""
echo "Enter the domain you want to host BookStack and press [ENTER]: "
read DOMAIN

#myip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/') # this is only used for output/logging

NGINX_CONFIG_DIR=/usr/local/etc/nginx

# dunno what this does
#export DEBIAN_FRONTEND=noninteractive 
#
# make this nicer:
pkg update
pkg install -y git nginx curl mysql57-server
pkg install -y php71 php71-curl php71-mbstring php71-ldap php71-mcrypt php71-tidy php71-xml php71-zip php71-gd php71-mysqli php71-session php71-pdo_mysql php71-xmlwriter php71-xmlreader phpunit7-php71
pkg install -y php71-simplexml php71-dom php71-fileinfo php71-tokenizer

# Update ports and change default PHP version to 7.1, then make composer.
# Doing this because the precompiled version from pkg wants to use an old version of PHP,
# so we build it for 7.1.
# TODO: add logic to determine if ports is installed already, and if not, install it
#portsnap update 
#portsnap extract # make this only extract compser and required deps.

#portsnap fetch
#portsnap extract

# Modify ports default versions
sed -i.bak 's/PHP_DEFAULT?=.*$/PHP_DEFAULT?=7.1/' /usr/ports/Mk/bsd.default-versions.mk

# install composer
cd /usr/ports/devel/php-composer && make -DBATCH install clean # -DBATCH accepts all default answers


# enable mysql
sysrc mysql_enable="YES"
# sysrc mysql_args="--bind-address=127.0.0.1" # not sure if needed
service mysql-server restart # starts (if running, restarts)
# Set up database
# TODO: add option to also run mysql_secure_installation with answer file
# this is probably not the best way to do this..
#touch /root/.my.cnf
MY_SECRET="`tail -n1 /root/.mysql_secret`"
#printf "[client]\npassword=$MY_SECRET\n" >> /root/.my.cnf
#mysql --user=root <<_EOF_
#db_root_password=root
#echo $MY_SECRET
#mysql --user=root -p${MY_SECRET} --connect-expired-password --execute="UPDATE mysql.user SET Password=PASSWORD('root') WHERE User='root';"
#mysql --user=root -p${MY_SECRET} --connect-expired-password --execute="UPDATE mysql.user SET Password=PASSWORD('root') WHERE User='root';"
mysql --user=root -p${MY_SECRET} --connect-expired-password --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY 'MySQL!57';"
#mysql --user=root -p'MySQL!57' --execute="uninstall plugin validate_password;"
mysql --user=root -p'MySQL!57' --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';"
mysql --user=root --password=root --execute="DELETE FROM mysql.user WHERE User='';"
mysql --user=root --password=root --execute="DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql --user=root --password=root --execute="DROP DATABASE IF EXISTS test;"
mysql --user=root --password=root --execute="DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

#_EOF_

# ensure DB_PASS has at least one lower, upper, digit, and punct.  Just [:alnum:] can be only one case or no punct
DB_PASS="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13)"
mysql --user=root --password=root --execute="CREATE DATABASE bookstack;"
mysql --user=root --password=root --execute="CREATE USER 'bookstack'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql --user=root --password=root --execute="GRANT ALL ON bookstack.* TO 'bookstack'@'localhost';"
mysql --user=root --password=root --execute="FLUSH PRIVILEGES;"

# rm /root/.my.cnf # disabled for debugging

# Download BookStack
BOOKSTACK_DIR="/usr/local/www/bookstack"
git clone https://github.com/BookStackApp/BookStack.git --branch release --single-branch $BOOKSTACK_DIR

#cd $BOOKSTACK_DIR # don't do this.. it's bad.

# Install BookStack composer dependancies
composer install -d $BOOKSTACK_DIR --no-scripts

# Copy and update BookStack environment variables

cp $BOOKSTACK_DIR/.env.example $BOOKSTACK_DIR/.env
sed -i.bak 's/DB_DATABASE=.*$/DB_DATABASE=bookstack/' $BOOKSTACK_DIR/.env
sed -i.bak 's/DB_USERNAME=.*$/DB_USERNAME=bookstack/' $BOOKSTACK_DIR/.env
sed -i.bak "s/DB_PASSWORD=.*\$/DB_PASSWORD=$DB_PASS/" $BOOKSTACK_DIR/.env
# Generate the application key
php $BOOKSTACK_DIR/artisan key:generate --no-interaction --force
# Migrate the databases
php $BOOKSTACK_DIR/artisan migrate --no-interaction --force

# Set file and folder permissions
chown -R www:www $BOOKSTACK_DIR/bootstrap/cache $BOOKSTACK_DIR/public/uploads $BOOKSTACK_DIR/storage && chmod -R 755 $BOOKSTACK_DIR/bootstrap/cache $BOOKSTACK_DIR/public/uploads $BOOKSTACK_DIR/storage

# Add nginx configuration
#curl https://raw.githubusercontent.com/BookStackApp/devops/master/config/nginx > $NGINX_CONFIG_DIR/sites-available/bookstack
#mkdir -p $NGINX_CONFIG_DIR/sites-available/bookstack
#sed -i.bak "s/bookstack.dev/$DOMAIN/" $NGINX_CONFIG_DIR/sites-available/bookstack
#ln -s $NGINX_CONFIG_DIR/sites-available/bookstack $NGINX_CONFIG_DIR/sites-enabled/bookstack
mv $NGINX_CONFIG_DIR/nginx.conf $NGINX_CONFIG_DIR/nginx.conf.orig
cp /nas/Scripts/sh/nginx.conf $NGINX_CONFIG_DIR

# Remove the default nginx configuration
#rm $NGINX_CONFIG_DIR/sites-enabled/default

# Restart nginx to load new config
sysrc nginx_enable="YES"
sysrc mysql_enable="YES"
sysrc mysql_args="--bind-address=127.0.0.1"
sysrc php_fpm_enable="YES"

service mysql-server restart
service php-fpm restart
service nginx restart

echo ""
echo "Setup Finished.  Your BookStack instance should now be installed."
echo "You can login with the email 'admin@admin.com' and password of 'password'."
#echo "MySQL was installed witroot password 'root', It is recommended that you change it."
#echo 'mysql --user=root -p'root' --execute="ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';"'
echo "Changing MySQL root password:"
mysqladmin password --user=root --password=root
#echo "You can access your BookStack instance at: http://$myip/"