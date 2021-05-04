#!/usr/bin/env bash
echo "Running configuration script"
export DEBIAN_FRONTEND=noninteractive

echo "US/Central" | sudo tee /etc/timezone
dpkg-reconfigure --frontend noninteractive tzdata

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
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367
cp $TEMPLATES_PATH/etc/apt/sources.list.d/* /etc/apt/sources.list.d/

echo "Install essential software pacakges"
apt-get -qq update
apt-get -qq install -y ansible

echo "Install Node"
curl -sL https://deb.nodesource.com/setup_14.x | sudo bash -
sudo apt -y install nodejs
sudo npm install --global yarn

echo "Install ETL software packages"
apt-get -qq install -y subversion git gpg unzip python3-pip acl
apt-get -qq install -y xlsx2csv

echo "Install web server tools"
apt-get -qq install -y apache2
chown -R www-data /var/www/

echo "Install SimpleBook depdendencies"
apt-get -qq install -y ca-certificates fonts-liberation libappindicator3-1 libasound2
apt-get -qq install -y libatk-bridge2.0-0 libatk1.0-0 libc6libcairo2 libcups2 libdbus-1-3
apt-get -qq install -y libexpat1 libfontconfig1 libgbm1 libgcc1 libglib2.0-0 libgtk-3-0 libnspr4
apt-get -qq install -y libnss3 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1
apt-get -qq install -y libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6
apt-get -qq install -y libxrandr2 libxrender1 libxss1 libxtst6 lsb-release wget xdg-utils
apt-get -qq install -y pipenv
npm install -g yarn
cd /home/vagrant/SimpleBook/services/api/mw2pdf
yarn install
cd /home/vagrant/SimpleBook/services/api
pipenv install

echo "Set up Redis"
cd /home/vagrant
wget http://download.redis.io/redis-stable.tar.gz
tar xvzf redis-stable.tar.gz
rm redis-stable.tar.gz
cd redis-stable && make
sudo cp src/redis-server /usr/local/bin/
sudo cp src/redis-cli /usr/local/bin/
sudo mkdir /etc/redis
sudo mkdir -p /var/redis/6379
sudo cp $TEMPLATES_PATH/etc/init.d/redis_6379 /etc/init.d/redis_6379
sudo cp $TEMPLATES_PATH/etc/redis/6379.conf /etc/redis/6379.conf
sudo chmod 722 /etc/init.d/redis_6379
sudo update-rc.d redis_6379 defaults
sudo /etc/init.d/redis_6379 start

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

# Set up SimpleBook
cp $TEMPLATES_PATH/etc/supervisor/conf.d/simplebook.conf /etc/supervisor/conf.d/simplebook.conf
sudo supervisorctl update simplebook
sudo supervisorctl update simplebook-api

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
	rm -fr /var/www/html/100Change2020/extensions/Collection
	ln -s /home/vagrant/SimpleBook /var/www/html/100Change2020/extensions/Collection
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
	rm -fr /var/www/html/LLIIA2020/extensions/Collection
	ln -s /home/vagrant/SimpleBook /var/www/html/LLIIA2020/extensions/Collection
fi

# Install the Climte2030 competition
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
	rm -fr /var/www/html/Climate2030/extensions/Collection
	ln -s /home/vagrant/SimpleBook /var/www/html/Climate2030/extensions/Collection
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
	rm -fr /var/www/html/LoneStar2020/extensions/Collection
	ln -s /home/vagrant/SimpleBook /var/www/html/LoneStar2020/extensions/Collection
fi

echo "ALL DONE"
