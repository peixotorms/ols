#!/bin/bash

##############################################################################
#		OpenLiteSpeed, LetsEncrypt                                           #
#       PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI                       #
#       Percona Server 8.0 for MySQL, Postfix and Redis                      #
#		Author: Raul Peixoto, WP Raiser										 #
##############################################################################

# defaults
OLS_USER="admin"
OLS_PASS=""
VERBOSE=0
FUNCTION_NAMES="update_system,setup_sshd,setup_repositories,setup_firewall,install_basic_packages,install_ols,install_php,install_wp_cli,install_percona,install_redis,install_postfix"

# Function to print usage instructions
function print_usage() {
	echo ""
	printf "    "
	echo "Usage: bash [-f <function_names>] [-v] [-h]"
	
	echo ""
	printf "    "
	echo "Options:"
	
	echo ""
	printf "        "
	echo "-f          Run a comma-separated list of function names:"
	printf "                        "
	IFS=',' read -ra FUNC_NAMES <<< "update_system,setup_sshd,setup_repositories,setup_firewall,install_basic_packages,install_ols,install_php,install_wp_cli,install_percona,install_redis,install_postfix"
	for FUNC_NAME in "${FUNC_NAMES[@]}"; do
		printf "%s\n                        " "$FUNC_NAME"
	done
	
	echo ""
	printf "        "
	echo "-u          Customize OpenLiteSpeed username"
	
	echo ""
	printf "        "
	echo "-p          Customize OpenLiteSpeed password"
		
	echo ""
	printf "        "
	echo "-v          Enable verbose mode"
	
	echo ""
	printf "        "
	echo "-h          Show this help message"
	
	echo ""
	printf "    "
	echo "Examples:"
	
	echo ""
	printf "        "
	echo "./ols.sh | bash -s -f install_ols,install_php"
	printf "        "
	echo "./ols.sh -f install_ols,install_php"
	echo ""
}


# Parse command-line arguments
while getopts ":f:vh" opt; do
	case ${opt} in
		f ) # Run specific function(s)
			FUNCTION_NAMES=$(echo "$OPTARG" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | uniq | tr '\n' ',')
			;;
		u ) # Set OLS_USER
			if [ -n "$OPTARG" ]; then
				OLS_USER="$OPTARG"
			else
				echo "Error: OLS_USER cannot be empty." >&2
				exit 1
			fi
			;;
		p ) # Set OLS_PASS
			if [ -n "$OPTARG" ]; then
				OLS_PASS="$OPTARG"
			else
				echo "Error: OLS_PASS cannot be empty." >&2
				exit 1
			fi
			;;
		v ) # Enable verbose mode
			VERBOSE=1
			;;
		h ) # Print usage instructions
			print_usage
			exit 0
			;;
		\? ) # Invalid option
			echo "Invalid option: -$OPTARG" >&2
			print_usage
			exit 1
			;;
		: ) # Option requires an argument
			echo "Option -$OPTARG requires an argument." >&2
			print_usage
			exit 1
			;;
	esac
done



# START FUNCTIONS


# This function executes the given command and suppresses its output if the VERBOSE variable is not set to '1'. 
# Usage: silent <command>
function silent { if [ "${VERBOSE}" = '1' ]; then "$@"; else "$@" >/dev/null 2>&1; fi; }

# This function creates a 32-character password with three special characters in a random position
gen_rand_pass() { random_string=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32); for i in {1..3}; do pos=$((RANDOM % 24 + 5)); special_char=('-' '_' ','); random_string="${random_string:0:$(($pos-1))}${special_char[RANDOM % 3]}${random_string:$pos}"; done; echo "$random_string"; }; 


# This function calculates memory configurations for various components based on the available system memory and CPU cores
calculate_memory_configs() {

	local OPTION=$1
	local TOTAL_RAM=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo)/1024))
	local RAM=$(($TOTAL_RAM - 256))
	local REDIS_MEM=$(($RAM/4))
	[ $REDIS_MEM -gt 4096 ] && REDIS_MEM=4096
	local MYSQL_MEM=$(($RAM/2))
	local PHP_MEM=$(($RAM - $REDIS_MEM - $MYSQL_MEM))
	
	case $OPTION in
		"REDIS_MEM")
				echo $REDIS_MEM
				;;
		"MYSQL_MEM")
				echo $MYSQL_MEM
				;;
		"PHP_MEM")
				echo $PHP_MEM
				;;
		"MYSQL_POOL_COUNT")
				local CPU_CORES=$(nproc)
				local MYSQL_POOL_COUNT=$(($MYSQL_MEM/1024))
				local MYSQL_MAX_POOL_COUNT=$(($CPU_CORES*4/5))
				[ $MYSQL_POOL_COUNT -gt $MYSQL_MAX_POOL_COUNT ] && MYSQL_POOL_COUNT=$MYSQL_MAX_POOL_COUNT
				[ $MYSQL_POOL_COUNT -lt 1 ] && MYSQL_POOL_COUNT=1
				echo $MYSQL_POOL_COUNT
				;;
		"PHP_POOL_COUNT")
				local CPU_CORES=$(nproc)
				local PHP_POOL_COUNT=$(($PHP_MEM/48))
				local MAX_PHP_POOL_COUNT=$(($CPU_CORES*2))
				[ $PHP_POOL_COUNT -gt $MAX_PHP_POOL_COUNT ] && PHP_POOL_COUNT=$MAX_PHP_POOL_COUNT
				[ $PHP_POOL_COUNT -lt 1 ] && PHP_POOL_COUNT=1
				echo $PHP_POOL_COUNT
				;;
		"MYSQL_LOG_SIZE")
				local MYSQL_LOG_SIZE=$(($MYSQL_MEM/4))
				[ $MYSQL_LOG_SIZE -gt 2048 ] && MYSQL_LOG_SIZE=2048
				[ $MYSQL_LOG_SIZE -lt 32 ] && MYSQL_LOG_SIZE=32
				echo $MYSQL_LOG_SIZE
				;;
	esac
	
	# usage
	#REDIS_MEM=$(calculate_memory_configs "REDIS_MEM")
	#MYSQL_MEM=$(calculate_memory_configs "MYSQL_MEM")
	#PHP_MEM=$(calculate_memory_configs "PHP_MEM")
	#MYSQL_POOL_COUNT=$(calculate_memory_configs "MYSQL_POOL_COUNT")
	#PHP_POOL_COUNT=$(calculate_memory_configs "PHP_POOL_COUNT")
	#MYSQL_LOG_SIZE=$(calculate_memory_configs "MYSQL_LOG_SIZE")
	
}


# This function updates the system and disables hints on pending kernel upgrades
function update_system
{
	if [ -d /etc/needrestart/conf.d ]; then
		echo 'Disabling pending kernel upgrade notice...'
		echo -e "\$nrconf{restart} = 'l';\n\$nrconf{kernelhints} = 0;" > /etc/needrestart/conf.d/disable.conf
	fi
	
	DEBIAN_FRONTEND=noninteractive silent apt update
	DEBIAN_FRONTEND=noninteractive silent apt upgrade -y
	DEBIAN_FRONTEND=noninteractive silent apt autoremove -y
}


# This function downloads and updates configuration files for sshd
function setup_sshd
{
	
	# download sshd_config
	echo -n "Updating sshd_config... "
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/sshd/sshd_config > /tmp/sshd_config
	cat /tmp/sshd_config | grep -q "ListenAddress" && cp /tmp/sshd_config /etc/ssh/sshd_config && echo "sshd_config updated." || echo "Error downloading sshd_config ..."
	rm /tmp/sshd_config
	service sshd restart
	
}


# This function sets up the necessary repositories for Percona, OpenLiteSpeed and PHP
function setup_repositories
{
	# percona
	echo "Adding Percona repositories..."
	silent curl -sO https://repo.percona.com/apt/percona-release_latest.generic_all.deb
	silent apt-get -y -f install gnupg2 lsb-release ./percona-release_latest.generic_all.deb
	
	# ols
	echo "Adding OLS repositories..."
	wget -q -O - https://repo.litespeed.sh | silent bash
	
	# Add ondrej/php PPA for PHP packages, if not added already
	echo "Adding PHP repositories..."
	if ! grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -q "ondrej/php"; then
		silent add-apt-repository -y ppa:ondrej/php
	fi

	# update
	DEBIAN_FRONTEND=noninteractive silent apt update
	DEBIAN_FRONTEND=noninteractive silent apt upgrade -y >/dev/null 2>&1
}


# This function sets up and configures the firewall using ufw (Uncomplicated Firewall).
function setup_firewall
{
	# start
	echo "Updating firewall policy..."
	
	# reinstall and reset firewall
	silent iptables --flush
	silent iptables --delete-chain
		 
	# Check if ufw is already installed, and only reinstall if not
	if ! command -v ufw &> /dev/null; then
		DEBIAN_FRONTEND=noninteractive silent apt install -y ufw
		echo "y" | silent ufw reset
	fi

	# default policy
	silent ufw default deny incoming
	silent ufw default allow outgoing
	silent ufw default allow routed

	# open or block ports: 
	silent ufw allow 22/tcp		 # ssh default
	silent ufw allow 999/tcp     # ssh custom
	silent ufw allow 123/udp	 # ntp
	silent ufw allow 51820/udp	 # wg
	silent ufw allow 80/tcp		 # http
	silent ufw allow 443/tcp	 # https
	silent ufw allow 443/udp	 # http3
	silent ufw allow 7080/tcp	 # ols

	# save and enable
	echo "y" | silent ufw enable
	# ufw status verbose

}


# Basic packages: certbot, pv, pigz, curl, wget, zip, memcached, etc
function install_basic_packages() {
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" certbot pv pigz curl wget zip memcached
}


# OpenLiteSpeed web server and its PHP 8.0 packages.
function install_ols() {

	# start
	echo "Installing OpenLiteSpeed... "

	# Install OLS
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" openlitespeed lsphp80 lsphp80-common lsphp80-curl
	
	# Set admin credentials
	if [ $? = 0 ] ; then
		[ -z "$OLS_PASS" ] && OLS_PASS=$(gen_rand_pass)
		ENCRYPT_PASS=`"/usr/local/lsws/admin/fcgi-bin/admin_php" -q "/usr/local/lsws/admin/misc/htpasswd.php" $OLS_PASS`
		if [ $? = 0 ] ; then
			echo "${OLS_USER}:$ENCRYPT_PASS" > "/usr/local/lsws/admin/conf/htpasswd"
			if [ $? = 0 ] ; then
				echo $OLS_PASS > /usr/local/lsws/password.user
			fi
		fi
	fi
	
	# download ols config
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/ols/httpd_config.conf > /tmp/httpd_config.conf
	cat /tmp/httpd_config.conf | grep -q "autoLoadHtaccess" && cp /tmp/httpd_config.conf /usr/local/lsws/conf/httpd_config.conf && echo "httpd_config.conf updated." || echo "Error downloading httpd_config.conf ..."
	rm /tmp/httpd_config.conf
	chown -R lsadm:lsadm /usr/local/lsws/conf/
	systemctl restart lshttpd
	
	# create self signed ssl
	echo "Installing self signed ssl..."
	SSL_COUNTRY="${SSL_COUNTRY:-US}"
	SSL_STATE="${SSL_STATE:-New Jersey}"
	SSL_LOCALITY="${SSL_LOCALITY:-Virtual}"
	SSL_ORG="${SSL_ORG:-LiteSpeedCommunity}"
	SSL_ORGUNIT="${SSL_ORGUNIT:-self}"
	SSL_HOSTNAME="${SSL_HOSTNAME:-web}"
	SSL_EMAIL="${SSL_EMAIL:-.}"
	COMMNAME=$(hostname)
	CSR=server.csr
	KEY=server.key
	CERT=server.crt		
	echo -e "[req]\nprompt=no\ndistinguished_name=openlitespeed\n[openlitespeed]\ncommonName = ${COMMNAME}\ncountryName = ${SSL_COUNTRY}\nlocalityName = ${SSL_LOCALITY}\norganizationName = ${SSL_ORG}\norganizationalUnitName = ${SSL_ORGUNIT}\nstateOrProvinceName = ${SSL_STATE}\nemailAddress = ${SSL_EMAIL}\nname = openlitespeed\ninitials = CP\ndnQualifier = openlitespeed\n[server_exts]\nextendedKeyUsage=1.3.6.1.5.5.7.3.1" > $CSR
	openssl req -x509 -config $CSR -extensions 'server_exts' -nodes -days 820 -newkey rsa:2048 -keyout ${KEY} -out ${CERT} >/dev/null 2>&1
	rm -f $CSR
	mv ${KEY}	/usr/local/lsws/conf/$KEY
	mv ${CERT} /usr/local/lsws/conf/$CERT
	chmod 0600 /usr/local/lsws/conf/$KEY
	chmod 0600 /usr/local/lsws/conf/$CERT
	
}


# PHP FPM and its extensions for different PHP versions (7.4, 8.0, 8.1, and 8.2).
function install_php() {

	# start
	echo "Installing PHP..."
	
	# packages
	all_packages=""
	for version in 7.4 8.0 8.1 8.2; do
		available_packages=""
		for package in php${version}-fpm php${version}-cli php${version}-bcmath php${version}-common php${version}-curl php${version}-gd php${version}-gmp php${version}-imap php${version}-intl php${version}-mbstring php${version}-mysql php${version}-pgsql php${version}-soap php${version}-tidy php${version}-xml php${version}-xmlrpc php${version}-zip php${version}-opcache php${version}-xsl php${version}-imagick php${version}-redis php${version}-memcached; do
			if apt-cache show $package > /dev/null 2>&1; then
			available_packages="$available_packages $package"
			fi
		done
		if [[ ! -z $available_packages ]]; then
			all_packages="$all_packages $available_packages"
		fi
	done
	if [[ ! -z $all_packages ]]; then
		DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" $all_packages
	else
		echo "No packages available for any PHP version."
	fi
	
	# configure
	# Download php.ini file
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/php/php.ini > /tmp/php.ini
	if cat /tmp/php.ini | grep -q "max_input_vars"; then find /etc/php -type f -iname php.ini -exec cp /tmp/php.ini {} \; && echo "php.ini files updated."; else echo "Error downloading php.ini ..."; fi
	rm /tmp/php.ini
	
	# cli adjustments
	find /etc/php -type f -path "*cli/*" -iname php.ini | while read file; do
		sed -i "s/^max_input_time.*$/max_input_time = 7200/" "$file"
		sed -i "s/^max_execution_time.*$/max_execution_time = 7200/" "$file"
		sed -i "s/^memory_limit.*$/memory_limit = 4096M/" "$file"
		sed -i "s/^opcache\.enable.*$/opcache.enable=0/" "$file"		
	done
		
	# Download php-fpm.conf
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/php/php-fpm.conf > /tmp/php-fpm.conf
	if cat /tmp/php-fpm.conf | grep -q "error_log"; then find /etc/php -type f -iname php-fpm.conf -exec cp /tmp/php-fpm.conf {} \; && echo "php-fpm.conf file updated."; else echo "Error downloading php-fpm.conf ..."; fi
	rm /tmp/php-fpm.conf
	find /etc/php -type f -iname php-fpm.conf | while read file; do
		version=$(echo "$file" | awk -F'/' '{print $4}')
		sed -i "s/#php_ver#/$version/g" "$file"
		systemctl stop php${version}-fpm
	done
	
	# delete default pools
	find /etc/php/ -type f -path "*/pool.d/*" -name "www.conf" -delete
	
	# restart if other pools exist
	find /etc/php/ -type f -path "*/pool.d/*" -name "*.conf" | while read file; do
		version=$(echo "$file" | awk -F'/' '{print $4}')
		systemctl restart php${version}-fpm
	done
	
}


# WP-CLI, a command-line tool for managing WordPress installations.
function install_wp_cli() {

	# start
	echo "Installing WP-CLI..."
	
	if ! command -v wp &> /dev/null; then INSTALLED_VERSION="0.0.0"; else INSTALLED_VERSION=$(wp --version --allow-root | awk '{print $2}'); fi
	LATEST_VERSION=$(curl -s https://api.github.com/repos/wp-cli/wp-cli/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' | sed 's/^v//')
	if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
		silent curl -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
		chmod +x wp-cli.phar
		mv wp-cli.phar /usr/local/bin/wp
		[ ! -f /usr/bin/wp ] && sudo ln -s /usr/local/bin/wp /usr/bin/wp
		echo "Updated wp from version $INSTALLED_VERSION to $LATEST_VERSION"
	fi
	
}


# Percona Server, a high-performance alternative to MySQL, for database management.
function install_percona() {
	
	# start
	echo "Installing Percona Server..."
	
	# Install Percona
	silent percona-release setup ps80 
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" percona-server-server percona-server-client
	
	# download my.cnf
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/sql/my.cnf > /tmp/my.cnf
	cat /tmp/my.cnf | grep -q "mysqld" && cp /tmp/my.cnf /etc/mysql/my.cnf && echo "my.cnf updated." || echo "Error downloading my.cnf ..."
	rm /tmp/my.cnf
	MYSQL_MEM=$(calculate_memory_configs "MYSQL_MEM")
	MYSQL_POOL_COUNT=$(calculate_memory_configs "MYSQL_POOL_COUNT")
	MYSQL_LOG_SIZE=$(calculate_memory_configs "MYSQL_LOG_SIZE")	
	sed -i "s/^innodb_buffer_pool_instances.*$/innodb_buffer_pool_instances	 = $MYSQL_POOL_COUNT/" /etc/mysql/my.cnf
	sed -i "s/^innodb_buffer_pool_size.*$/innodb_buffer_pool_size				= ${MYSQL_MEM}M/" /etc/mysql/my.cnf
	sed -i "s/^innodb_log_file_size.*$/innodb_log_file_size					 = ${MYSQL_LOG_SIZE}M/" /etc/mysql/my.cnf
	systemctl restart mysql
	
	
	# Stop MySQL service
	sudo systemctl stop mysql
	
	# Create the directory for the UNIX socket file, if it doesn't exist
	sudo mkdir -p /var/run/mysqld
	sudo chown mysql:mysql /var/run/mysqld
	
	# Start MySQL with --skip-grant-tables and --skip-networking
	sudo mysqld_safe --skip-grant-tables --skip-networking &
	
	# Sleep for a few seconds to allow MySQL to start
	sleep 5
	
	# ensure root uses auth_socket without pass
	mysql -u root -e "FLUSH PRIVILEGES; UPDATE mysql.user SET plugin='auth_socket' WHERE user='root'; FLUSH PRIVILEGES;"
	
	# use root password instead
	# ROOTPASSWORD=$(gen_rand_pass)
	# mysql -u root -e "FLUSH PRIVILEGES; UPDATE mysql.user SET plugin='caching_sha2_password' WHERE user='root'; FLUSH PRIVILEGES;"
	# mysql -u root -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOTPASSWORD'; FLUSH PRIVILEGES;"
	# echo -n "$ROOTPASSWORD" > /etc/mysql/root.pass.log
	# chmod 600 /etc/mysql/root.pass.log
	# echo "MySQL root password has been changed to $ROOTPASSWORD on /etc/mysql/root.pass.log"
	
	# Find and kill mysqld_safe process
	pkill mysql
	
	# Start MySQL service
	sudo systemctl start mysql
	
}


# Redis, an open-source mail transfer agent (MTA) for routing and delivering email.
function install_redis() {
	
	# start
	echo "Installing Redis..."
	
	# install
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" redis-server
	
	# redis config
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/redis/redis.conf > /tmp/redis.conf
	cat /tmp/redis.conf | grep -q "maxmemory" && cp /tmp/redis.conf /etc/redis/redis.conf && echo "redis.conf updated." || echo "Error downloading redis.conf ..."
	rm /tmp/redis.conf
	REDIS_MEM=$(calculate_memory_configs "REDIS_MEM")
	sed -i "s/^maxmemory 128mb.*$/maxmemory ${REDIS_MEM}mb/" /etc/redis/redis.conf
	service redis-server restart
	
}


# Postfix, an open-source mail transfer agent (MTA) for routing and delivering email.
function install_postfix() {

	# start
	echo "Installing Postfix..."

	# install
	debconf-set-selections <<< "postfix postfix/mailname string localhost"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" ssl-cert postfix mailutils
	
	# download postfix	
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/postfix/main.cf > /tmp/main.cf
	cat /tmp/main.cf | grep -q "smtpd_banner" && cp /tmp/main.cf /etc/postfix/main.cf && echo "main.cf updated." || echo "Error downloading main.cf ..."
	rm /tmp/main.cf
	echo 'postmaster: /dev/null\nroot: /dev/null' | sudo tee /etc/aliases > /dev/null
	systemctl restart postfix
	
}

# END FUNCTIONS


# Run selected functions in order
for FUNCTION_NAME in $(echo "$FUNCTION_NAMES" | tr ',' '\n' | uniq); do
	case $FUNCTION_NAME in
		"update_system")
			update_system
			;;
		"setup_sshd")
			setup_sshd
			;;
		"setup_repositories")
			setup_repositories
			;;
		"setup_firewall")
			setup_firewall
			;;
		"install_basic_packages")
			install_basic_packages
			;;
		"install_ols")
			install_ols
			;;
		"install_php")
			install_php
			;;
		"install_wp_cli")
			install_wp_cli
			;;
		"install_percona")
			install_percona
			;;
		"install_redis")
			install_redis
			;;
		"install_postfix")
			install_postfix
			;;
		*)
			echo "Invalid function name: $FUNCTION_NAME"
			exit 1
			;;
	esac
done

echo "All done!"
