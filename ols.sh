#!/bin/bash

##############################################################################
#    Open LiteSpeed + PerconaDB setup                                        #
#    Author: Raul Peixoto, WP Raiser                                         #
#    Based on: LiteSpeed 1-Click Install OLS                                 #
##############################################################################

VERBOSE=1

# This function executes the given command and suppresses its output if the VERBOSE variable is not set to '1'. 
# It can be useful when running commands that may produce a lot of output or when you only want to see the output in verbose mode. 
# Usage: silent <command>
function silent { if [ "${VERBOSE}" = '1' ]; then "$@"; else "$@" >/dev/null 2>&1; fi; }


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
        echo 'List Restart services only'
        echo -e "\$nrconf{restart} = 'l';\n\$nrconf{kernelhints} = 0;" > /etc/needrestart/conf.d/disable.conf
    fi
	
	DEBIAN_FRONTEND=noninteractive silent apt update
	DEBIAN_FRONTEND=noninteractive silent apt upgrade -y
	DEBIAN_FRONTEND=noninteractive silent apt autoremove -y
}



# This function sets up the necessary repositories for Percona, OpenLiteSpeed and PHP
function setup_repositories
{
    # percona
	echo "Adding Percona repo..."
    silent curl -sO https://repo.percona.com/apt/percona-release_latest.generic_all.deb
    silent apt-get -y -f install gnupg2 lsb-release ./percona-release_latest.generic_all.deb
	
	# ols
	echo "Adding OLS repositories..."
	silent wget -q -O - https://repo.litespeed.sh | sudo bash
	
	# Add ondrej/php PPA for PHP packages, if not added already
	echo "Adding PHP repositories..."
    if ! grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -q "ondrej/php"; then
        echo "Adding ondrej/php PPA for PHP packages..."
        silent add-apt-repository -y ppa:ondrej/php
    fi

    # update
    DEBIAN_FRONTEND=noninteractive silent apt update
    DEBIAN_FRONTEND=noninteractive silent apt upgrade -y >/dev/null 2>&1
}


# This function sets up and configures the firewall using ufw (Uncomplicated Firewall).
function setup_firewall
{

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
	silent ufw allow 22/tcp     # ssh default
	silent ufw allow 999/tcp    # ssh custom
	silent ufw allow 123/udp    # ntp
	silent ufw allow 51820/udp  # wg
	silent ufw allow 80/tcp     # http
	silent ufw allow 443/tcp    # https
	silent ufw allow 443/udp    # http3
	silent ufw allow 7080/tcp   # ols

	# save and enable
	echo "y" | silent ufw enable
	# ufw status verbose

}


# This function performs a variety of basic server setup tasks, including:
# 1. Reconfiguring timezone and locale settings.
# 2. Setting the default text editor to nano.
# 3. Adding 'localhost' entry to /etc/hosts if it doesn't exist.
# 4. Updating /etc/security/limits.conf with nofile limits.
# 5. Creating or resizing the swapfile to a permanent 2GB size.
# 6. Ensuring idempotency for /etc/security/limits.conf and /etc/fstab by removing comments and empty lines.
function setup_basic
{
    # Basic settings
    silent dpkg-reconfigure -f noninteractive tzdata
    silent locale-gen en_US en_US.utf8
    silent localectl set-locale LANG=en_US.utf8
    silent update-locale LC_ALL=en_US.utf8
    echo "SELECTED_EDITOR=\"/bin/nano\"" > /root/.selected_editor
    grep -qxF '127.0.0.1 localhost' /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts

    # Add limits to limits.conf only if they don't already exist
    if ! grep -qxF '* soft nofile 999999' /etc/security/limits.conf; then
        echo '* soft nofile 999999' >> /etc/security/limits.conf
    fi

    if ! grep -qxF '* hard nofile 999999' /etc/security/limits.conf; then
        echo '* hard nofile 999999' >> /etc/security/limits.conf
    fi

    # Check if the swap file already exists
	if [ ! -f /swapfile ]; then
	  # Create a new permanent swap of 2GB
	  echo "Creating a new permanent swap of 2GB..."
	  fallocate -l 2G /swapfile
	  chmod 600 /swapfile
	  mkswap /swapfile
	  swapon /swapfile
	  # Update /etc/fstab to reflect the new size
	  bash -c 'echo "/swapfile swap swap defaults 0 0" >> /etc/fstab'
	else
	  # Check if swap is enabled
	  if grep -q "swapfile" /proc/swaps; then
		# Check the current swap size
		swap_size_gb=$(free --giga | awk '/Swap/ {print $2}')
		
		# If the swap size is not 2GB
		if [ $swap_size_gb -ne 2 ]; then
		  # Resize the swap to 2GB
		  echo "Resizing swap to 2GB..."
		  swapoff -a
		  dd if=/dev/zero of=/swapfile bs=1G count=2
		  chmod 600 /swapfile
		  mkswap /swapfile
		  swapon /swapfile
		  # Update /etc/fstab to reflect the new size
		  bash -c 'sed -i "/swapfile/c\\/swapfile swap swap defaults 0 0" /etc/fstab'
		fi
	  else
		# Create a new permanent swap of 2GB
		echo "Creating a new permanent swap of 2GB..."
		fallocate -l 2G /swapfile
		chmod 600 /swapfile
		mkswap /swapfile
		swapon /swapfile
		# Update /etc/fstab to reflect the new size
		bash -c 'echo "/swapfile swap swap defaults 0 0" >> /etc/fstab'
	  fi
	fi

    # Set up idempotency for limits.conf and fstab
    sed -i '/^#/d;/^$/d' /etc/security/limits.conf
    sed -i '/^#/d;/^$/d' /etc/fstab
}


# This function installs a variety of necessary packages for the server, including:
# 1. Basic packages: certbot, pv, pigz, curl, wget, zip, memcached, and redis-server.
# 2. OpenLiteSpeed web server and its PHP 8.0 packages.
# 3. PHP FPM and its extensions for different PHP versions (7.4, 8.0, 8.1, and 8.2).
# 4. WP-CLI, a command-line tool for managing WordPress installations.
# 5. Postfix, an open-source mail transfer agent (MTA) for routing and delivering email.
# 6. Percona Server, a high-performance alternative to MySQL, for database management.
function setup_packages
{

	# basic
	echo "Installing basic packages..."
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" certbot pv pigz curl wget zip memcached redis-server

	# ols
	echo "Installing OLS..."
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" openlitespeed lsphp80 lsphp80-common lsphp80-curl


	# php
	echo "Installing PHP FPM..."
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


	# wp cli
	echo "Installing wp-cli..."
	if ! command -v wp &> /dev/null; then INSTALLED_VERSION="0.0.0"; else INSTALLED_VERSION=$(wp --version --allow-root | awk '{print $2}'); fi
	LATEST_VERSION=$(curl -s https://api.github.com/repos/wp-cli/wp-cli/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' | sed 's/^v//')
	if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
	  silent curl -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
	  chmod +x wp-cli.phar
	  mv wp-cli.phar /usr/local/bin/wp	  
	  [ ! -f /usr/bin/wp ] && sudo ln -s /usr/local/bin/wp /usr/bin/wp
	  echo "Updated wp from version $INSTALLED_VERSION to $LATEST_VERSION"
	fi
	
	# postfix
	echo "Installing Postfix..."
	debconf-set-selections <<< "postfix postfix/mailname string localhost"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef"  ssl-cert postfix mailutils
	
	# percona
	echo "Installing Percona..."
	silent percona-release setup ps80 
    DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" percona-server-server percona-server-client

}


# This function generates and installs a self-signed SSL certificate for the server.
# The generated certificate is valid for 820 days and is made for OpenLiteSpeed
function setup_selfsigned_cert
{
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
    mv ${KEY}  /usr/local/lsws/conf/$KEY
    mv ${CERT} /usr/local/lsws/conf/$CERT
    chmod 0600 /usr/local/lsws/conf/$KEY
    chmod 0600 /usr/local/lsws/conf/$CERT
}


# This function downloads and updates configuration files for sshd, PHP, OpenLiteSpeed, MySQL, Redis, and Postfix.
function setup_configs
{
	
	# download sshd_config
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/sshd/sshd_config > /tmp/sshd_config
	cat /tmp/sshd_config | grep -q "ListenAddress" && cp /tmp/sshd_config /etc/ssh/sshd_config && echo "sshd_config updated." || echo "Error downloading sshd_config ..."
	rm /tmp/sshd_config
	service sshd restart	
	
	
	# download ols	
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/ols/httpd_config.conf > /tmp/httpd_config.conf
	cat /tmp/httpd_config.conf | grep -q "autoLoadHtaccess" && cp /tmp/httpd_config.conf /usr/local/lsws/conf/httpd_config.conf && echo "httpd_config.conf updated." || echo "Error downloading httpd_config.conf ..."
	rm /tmp/httpd_config.conf
	chown -R lsadm:lsadm /usr/local/lsws/conf/
	systemctl restart lshttpd
	
	
	# download my.cnf
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/sql/my.cnf > /tmp/my.cnf
	cat /tmp/my.cnf | grep -q "mysqld" && cp /tmp/my.cnf /etc/mysql/my.cnf && echo "my.cnf updated." || echo "Error downloading my.cnf ..."
	rm /tmp/my.cnf
	MYSQL_MEM=$(calculate_memory_configs "MYSQL_MEM")
	MYSQL_POOL_COUNT=$(calculate_memory_configs "MYSQL_POOL_COUNT")
	MYSQL_LOG_SIZE=$(calculate_memory_configs "MYSQL_LOG_SIZE")	
	sed -i "s/^innodb_buffer_pool_instances.*$/innodb_buffer_pool_instances   = $MYSQL_POOL_COUNT/" /etc/mysql/my.cnf
	sed -i "s/^innodb_buffer_pool_size.*$/innodb_buffer_pool_size       = ${MYSQL_MEM}M/" /etc/mysql/my.cnf
	sed -i "s/^innodb_log_file_size.*$/innodb_log_file_size           = ${MYSQL_LOG_SIZE}M/" /etc/mysql/my.cnf
	systemctl restart mysql
	
	
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
	
	# redis
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/redis/redis.conf > /tmp/redis.conf
	cat /tmp/redis.conf | grep -q "maxmemory" && cp /tmp/redis.conf /etc/redis/redis.conf && echo "redis.conf updated." || echo "Error downloading redis.conf ..."
	rm /tmp/redis.conf
	REDIS_MEM=$(calculate_memory_configs "REDIS_MEM")
	sed -i "s/^maxmemory 128mb.*$/maxmemory ${REDIS_MEM}mb/" /etc/redis/redis.conf
	service redis-server restart
	
	
	# download postfix	
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/postfix/main.cf > /tmp/main.cf
	cat /tmp/main.cf | grep -q "smtpd_banner" && cp /tmp/main.cf /etc/postfix/main.cf && echo "main.cf updated." || echo "Error downloading main.cf ..."
	rm /tmp/main.cf
	echo 'postmaster: /dev/null\nroot: /dev/null' | sudo tee /etc/aliases > /dev/null
	systemctl restart postfix
	
}



# install
update_system
setup_repositories
setup_firewall
setup_basic
setup_packages
setup_selfsigned_cert
setup_configs

# restart
#systemctl restart lshttpd
#systemctl restart mysql
#for version in 7.4 8.0 8.1 8.2; do service php${version}-fpm restart; done
echo "All done!"
