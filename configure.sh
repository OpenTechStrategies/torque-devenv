#!/usr/bin/env bash
echo "Running configuration script"
export DEBIAN_FRONTEND=noninteractive

echo "US/Central" | sudo tee /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata

echo "Add custom sources"
# Add ansible key
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367
cp $TEMPLATES_PATH/etc/apt/sources.list.d/* /etc/apt/sources.list.d/

echo "Install essential software pacakges"
apt-get -qq update
apt-get -qq install -y ansible

echo "Install web server tools"
apt-get -qq install -y apache2
chown -R www-data /var/www/

echo "Set up base ansible"
export ANSIBLE_ROLES_PATH=$ANSIBLE_ROLES_PATH:/home/vagrant/torque-sites/roles

# Define env variables for ansible templates
export DB_USERNAME=torque
export DB_PASSWORD=torque
export DEPLOYMENT_USER=$APP_USER
export MEDIAWIKI_ADMIN_PASSWORD=admin_password
export MEDIAWIKI_MWLIB_PASSWORD=mwlib_password
export MEDIAWIKI_CSV2WIKI_PASSWORD=csv2wiki_password
export MWLIB_INSTALL_DIRECTORY=/home/vagrant/mwlib/
export MYSQL_ROOT_PASSWORD=root
export ROOT_WEB_DIRECTORY=/var/www/html
export SIMPLESAML_INSTALL_DIRECTORY=/home/vagrant/simplesaml
export SIMPLESAML_OKTA_METADATA_NAME=$SIMPLESAML_OKTA_METADATA_NAME
export SIMPLESAML_OKTA_METADATA_URL=$SIMPLESAML_OKTA_METADATA_URL
export SIMPLESAML_SALT="$(LC_CTYPE=C tr -c -d '0123456789abcdefghijklmnopqrstuvwxyz' </dev/urandom | dd bs=32 count=1 2>/dev/null;echo)"
export TORQUEDATA_INSTALL_DIRECTORY=/home/vagrant/torquedata
export TORQUEDATA_SERVER_PORT=5000

export TORQUEDATA_PORT=$TORQUEDATA_SERVER_PORT
export HTML_DIRECTORY=$ROOT_WEB_DIRECTORY # Two names for the same thing so we reassign it here

# Set up folder access
mkdir /var/www/html/competitions
chown vagrant:www-data /var/www/html/competitions

# Install mwlib
echo "INSTALL MWLIB"
cd /home/vagrant/torque-sites/base/mwlib/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook mwlib.yml -i inv/local

# Install torquedata
echo "INSTALL TORQUEDATA"
cd /home/vagrant/torque-sites/base/torquedata/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook torquedata.yml -i inv/local

# Install simplesaml
echo "INSTALL SIMPLESAML"
cd /home/vagrant/torque-sites/base/simplesaml/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook simplesaml.yml -i inv/local

# Install the DemoView competition
echo "INSTALL DemoView competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/demoview
cd /home/vagrant/torque-sites/competitions/DemoView/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook DemoView.yml -i inv/local

echo "ALL DONE"
