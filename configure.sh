#!/usr/bin/env bash
echo "Running configuration script"
export DEBIAN_FRONTEND=noninteractive

echo "US/Central" | sudo tee /etc/timezone

# Let's read some configuration information
# from the user.
echo -n "Reading configuration..."
source /home/vagrant/configuration/configuration.env > /dev/null 2>&1
if [ $? -ne 0 ];
then
	echo "failure. Could not source your configuration/configuration.env file."
	exit 1
fi
echo "done."

# Now, check to make sure that all relevant variables are configured
# with sane values.
if [ -z "${OTS_SVN_USERNAME}" ];
then
	echo -n "Warning: Missing configuration of OTS_SVN_USERNAME; "
	echo "some functionality may not work."
fi

if [ -z "${OTS_SVN_PASSWORD}" ];
then
	echo -n "Warning: Missing configuration of OTS_SVN_PASSWORD; "
	echo "some functionality may not work."
fi

if [ -z "${DECRYPTION_PASSPHRASE}" ];
then
	echo -n "Warning: Missing configuration of DECRYPTION_PASSPHRASE; "
	echo "some functionality may not work."
fi

if [ -z "${SIMPLESAML_OKTA_METADATA_NAME}" ];
then
	echo -n "Warning: Missing configuration of SIMPLESAML_OKTA_METADATA_NAME; "
	echo "some functionality may not work."
fi

if [ -z "${SIMPLESAML_OKTA_METADATA_URL}" ];
then
	echo -n "Warning: Missing configuration of SIMPLESAML_OKTA_METADATA_URL; "
	echo "some functionality may not work."
fi

echo "Add custom sources"
# Add ansible key
mkdir /usr/local/share/keyrings
cp $TEMPLATES_PATH/usr/local/share/keyrings/* /usr/local/share/keyrings
cp $TEMPLATES_PATH/etc/apt/sources.list.d/* /etc/apt/sources.list.d/

echo "Install essential software pacakges"
apt-get -qq update
apt-get -qq install -y ansible python3

echo "Install ETL software packages"
apt-get -qq install -y subversion git gpg unzip python3-pip acl
apt-get -qq install -y xlsx2csv

echo "Install web server tools"
apt-get -qq install -y apache2
chown -R www-data /var/www/

echo "Install SimpleBook packages"
apt-get -qq install -y pipenv
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash - && sudo apt-get install -y nodejs

echo "Set up base ansible"
export ANSIBLE_ROLES_PATH=$ANSIBLE_ROLES_PATH:/home/vagrant/torque-sites/roles

# Configure apache
cp $TEMPLATES_PATH/etc/apache2/apache2.conf /etc/apache2/apache2.conf

# Configure subversion
mkdir /root/.subversion
export OTS_SVN_PASSWORD_LENGTH=${#OTS_SVN_PASSWORD}
export OTS_SVN_USERNAME_LENGTH=${#OTS_SVN_USERNAME}
cp -R $TEMPLATES_PATH/root/.subversion/* /root/.subversion
# SVN recently disabled non-interactive credential caching so we need to manually populate the cache
envsubst < /root/.subversion/auth/svn.simple/f3f481873e9051b96cd12601a28ac010.tmpl > /root/.subversion/auth/svn.simple/f3f481873e9051b96cd12601a28ac010
rm /root/.subversion/auth/svn.simple/f3f481873e9051b96cd12601a28ac010.tmpl

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
export MWLIB_INSTALL_DIRECTORY=/home/vagrant/installed_services/mwlib/
export SIMPLEBOOK_INSTALL_DIRECTORY=/home/vagrant/installed_services/SimpleBook # this MUST NOT END IN A SLASH
export MYSQL_ROOT_PASSWORD=root
export ROOT_WEB_DIRECTORY=/var/www/html
export SIMPLESAML_INSTALL_DIRECTORY=/home/vagrant/simplesaml
export SIMPLESAML_OKTA_METADATA_NAME=$SIMPLESAML_OKTA_METADATA_NAME
export SIMPLESAML_OKTA_METADATA_URL=$SIMPLESAML_OKTA_METADATA_URL
export GEOCODE_API_KEY=$GEOCODE_API_KEY
export SIMPLESAML_SALT="$(LC_CTYPE=C tr -c -d '0123456789abcdefghijklmnopqrstuvwxyz' </dev/urandom | dd bs=32 count=1 2>/dev/null;echo)"
export TORQUEDATA_INSTALL_DIRECTORY=/home/vagrant/torquedata
export TORQUEDATA_SERVER_PORT=5000
export SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe())')"

# There are two names used for for the same thing in various ansible scripts
# Rather than shave that yak at this stage, and rather than duplicate values,
# we're just reassigning here based on the arbitrarily selected canonical name.
export TORQUEDATA_PORT=$TORQUEDATA_SERVER_PORT
export HTML_DIRECTORY=$ROOT_WEB_DIRECTORY

# Set up folder access
mkdir /var/www/html/competitions
chown vagrant:www-data /var/www/html/competitions
mkdir /home/vagrant/installed_services

# Install SimpleBook
echo "INSTALL SIMPLEBOOK SERVER"
cd /home/vagrant/torque-sites/base/simplebook/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook simplebook.yml -i inv/local

# Overwrite SimpleBook server installation with mounted folder
# This replaces the server components of simplebook with our local / developer
# copy, and makes sure the developer copy has it's relevant packages installed.
#
# This means that if you "print" a book in a competition from devenv it will hit
# your local code copy instead of the ansible-installed code base (which will just
# be) whatever version is tagged in torque-sites as the one to use from github.
if [[ -L $SIMPLEBOOK_INSTALL_DIRECTORY ]]; then
  echo "WARNING: The SIMPLEBOOK_INSTALL_DIRECTORY is already a symlink, skipping mount linking step."
else
	rm -fr $SIMPLEBOOK_INSTALL_DIRECTORY
	ln -s /home/vagrant/SimpleBook $SIMPLEBOOK_INSTALL_DIRECTORY
	cd $SIMPLEBOOK_INSTALL_DIRECTORY/services/api
	su - $APP_USER -c "pipenv install"
	cd $SIMPLEBOOK_INSTALL_DIRECTORY/services/api/mw2pdf
	yarn install
	yarn build
	supervisorctl restart all
fi

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

# Install the LLIIA2020 competition
echo "INSTALL LLIIA2020 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/LLIIA2020
cd /home/vagrant/torque-sites/competitions/LLIIA2020/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook LLIIA2020.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/LLIIA2020'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/LLIIA2020/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/LLIIA2020/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
	rm -fr /var/www/html/LLIIA2020/extensions/SimpleBook
	ln -s /home/vagrant/SimpleBook /var/www/html/LLIIA2020/extensions/SimpleBook
fi

# Install the Climate2030 competition
echo "INSTALL Climate2030 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/Climate2030
cd /home/vagrant/torque-sites/competitions/Climate2030/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook Climate2030.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/Climate2030'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/Climate2030/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/Climate2030/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
fi

# Install the LoneStar2020 competition
echo "INSTALL LoneStar2020 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/LoneStar2020
cd /home/vagrant/torque-sites/competitions/LoneStar2020/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook LoneStar2020.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/LoneStar2020'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/LoneStar2020/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/LoneStar2020/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
fi

# Install the ECW2020 competition
echo "INSTALL ECW2020 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/ECW2020
cd /home/vagrant/torque-sites/competitions/ECW2020/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook ECW2020.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/ECW2020'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/ECW2020/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/ECW2020/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
fi

# Install the RacialEquity2030 competition
echo "INSTALL RacialEquity2030 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/RacialEquity2030
cd /home/vagrant/torque-sites/competitions/RacialEquity2030/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook RacialEquity2030.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/RacialEquity2030'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/RacialEquity2030/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/RacialEquity2030/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
fi

# Install the Democracy22 competition
echo "INSTALL Democracy22 competition"
export MEDIAWIKI_INSTALL_DIRECTORY=/var/www/html/competitions/Democracy22
cd /home/vagrant/torque-sites/competitions/Democracy22/ansible
envsubst < inv/local/group_vars/all.tmpl > inv/local/group_vars/all
ansible-playbook Democracy22.yml -i inv/local
if [ ETL_ENABLED ]
then
	export WIKI_URL='http://127.0.0.1/Democracy22'
	cd $OTS_DIR/clients/lever-for-change/torque-sites/Democracy22/data
	$OTS_DIR/utils/get-bigdata -c
	cd /home/vagrant/torque-sites/competitions/Democracy22/etl
	envsubst < config.py.tmpl > config.py
	./deploy -g "$DECRYPTION_PASSPHRASE" /home/vagrant/data/decrypted
fi


echo ""

echo "ALL DONE"
