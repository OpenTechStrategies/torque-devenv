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

echo "Install ETL software packages"
apt-get -qq install -y subversion git gpg unzip python3-pip acl

echo "Install web server tools"
apt-get -qq install -y apache2
chown -R www-data /var/www/

echo "Set up base ansible"
export ANSIBLE_ROLES_PATH=$ANSIBLE_ROLES_PATH:/home/vagrant/torque-sites/roles

# Configure apache
cp $TEMPLATES_PATH/etc/apache2/apache2.conf /etc/apache2/apache2.conf

# Configure subversion
mkdir /root/.subversion
cp -R $TEMPLATES_PATH/root/.subversion/* /root/.subversion

# Define env variables for ansible templates
export DB_USERNAME=torque
export DB_PASSWORD=torque
export DEPLOYMENT_USER=$APP_USER
export MEDIAWIKI_ADMIN_USERNAME=admin
export MEDIAWIKI_ADMIN_PASSWORD=admin_password
export MEDIAWIKI_MWLIB_USERNAME=mwlib
export MEDIAWIKI_MWLIB_PASSWORD=mwlib_password
export MEDIAWIKI_CSV2WIKI_USERNAME=csv2wiki
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

# There are two names used for for the same thing in various ansible scripts
# Rather than shave that yak at this stage, and rather than duplicate values,
# we're just reassigning here based on the arbitrarily selected canonical name.
export TORQUEDATA_PORT=$TORQUEDATA_SERVER_PORT
export HTML_DIRECTORY=$ROOT_WEB_DIRECTORY

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

# Set up ETL
if [ -z "$OTS_SVN_USERNAME" ]
then
	echo "Skipping ETL Setup (OTS_SVN_USERNAME not set)"
	ETL_ENABLED=false
else
	echo "Set up ETL"
	export OTS_DIR=/home/vagrant/data/ots
	mkdir -p $OTS_DIR/clients/lever-for-change/torque-sites
	mkdir -p $OTS_DIR/utils

	# Save SVN Credentials
	svn list \
		--username $OTS_SVN_USERNAME \
		--password $OTS_SVN_PASSWORD \
		https://svn.opentechstrategies.com/repos/ots/trunk/clients/lever-for-change > /dev/null

	# Check out ETL repositories
	svn checkout \
		https://svn.opentechstrategies.com/repos/ots/trunk/clients/lever-for-change/torque-sites \
		$OTS_DIR/clients/lever-for-change/torque-sites
	git clone \
		https://github.com/OpenTechStrategies/ots-tools.git \
		$OTS_DIR/utils

	mkdir /home/vagrant/data/decrypted
	cd /home/vagrant/torque-sites/etl
	pip3 install -e .
	ETL_ENABLED=true
fi

# Install the DemoView competition
echo "INSTALL DemoView competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/DemoView
cd /home/vagrant/torque-sites/competitions/DemoView/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook DemoView.yml -i inv/local

# Install the 100Change2020 competition
echo "INSTALL 100Change2020 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/100Change2020
cd /home/vagrant/torque-sites/competitions/100Change2020/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook 100Change2020.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/100Change2020'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/100Change2020/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/100Change2020/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
fi

echo "ALL DONE"
