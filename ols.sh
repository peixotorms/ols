#!/bin/bash

##############################################################################
#    Open LiteSpeed + PerconaDB setup                                        #
#    Author: Raul Peixoto, WP Raiser                                         #
#    Based on: LiteSpeed 1-Click Install OLS                                 #
##############################################################################


# run commands silently
function silent { if [ "${VERBOSE}" = '1' ]; then "$@"; else "$@" >/dev/null 2>&1; fi; }



# calculate limits
function calculate_memory() {
    # Detect the total amount of RAM in MB
    local TOTAL_RAM=$(($(awk '/MemTotal/ {print $2}' /proc/meminfo)/1024))

    # Subtract 256 MB from the total RAM to create a numeric RAM variable in MB
    local RAM=$(($TOTAL_RAM - 256))

    # Check if RAM is less than or equal to 200 MB
    if [ $RAM -le 200 ]
    then
        # Output a warning message and quit if RAM is less than or equal to 200 MB
        echo "Error: Not enough memory for the script to run."
        exit 1
    else
        # Count all CPU cores available
        local CPU_CORES=$(nproc)

        # Calculate the amount of RAM to be allocated for REDIS_MEM
        local REDIS_MEM=$(($RAM/4))
        if [ $REDIS_MEM -gt 4096 ]
        then
            REDIS_MEM=4096
        fi

        # Ensure that REDIS_MEM is an integer type
        REDIS_MEM=$(($REDIS_MEM/1))

        # Calculate the amount of RAM to be allocated for MYSQL_MEM
        local MYSQL_MEM=$(($RAM/2))

        # Ensure that MYSQL_MEM is an integer type
        MYSQL_MEM=$(($MYSQL_MEM/1))

        # Calculate the remaining amount of RAM to be allocated for PHP_MEM
        local PHP_MEM=$(($RAM-$REDIS_MEM-$MYSQL_MEM))

        # Ensure that PHP_MEM is an integer type
        PHP_MEM=$(($PHP_MEM/1))

        # Calculate MYSQL_POOL_COUNT
        local MYSQL_POOL_COUNT=$(($MYSQL_MEM/1024))
        local MYSQL_MAX_POOL_COUNT=$(($CPU_CORES*4/5))
        if [ $MYSQL_POOL_COUNT -gt $MYSQL_MAX_POOL_COUNT ]
        then
            MYSQL_POOL_COUNT=$MYSQL_MAX_POOL_COUNT
        fi
        if [ $MYSQL_POOL_COUNT -lt 1 ]
        then
            MYSQL_POOL_COUNT=1
        fi

        # Calculate PHP_POOL_COUNT
        local PHP_POOL_COUNT=$(($PHP_MEM/48))
        local MAX_PHP_POOL_COUNT=$(($CPU_CORES*2))
        if [ $PHP_POOL_COUNT -gt $MAX_PHP_POOL_COUNT ]
        then
            PHP_POOL_COUNT=$MAX_PHP_POOL_COUNT
        fi
        if [ $PHP_POOL_COUNT -lt 1 ]
        then
            PHP_POOL_COUNT=1
        fi

        # Calculate MYSQL_LOG_SIZE
        local MYSQL_LOG_SIZE=$(($MYSQL_MEM/4))
        if [ $MYSQL_LOG_SIZE -gt 2048 ]
        then
            MYSQL_LOG_SIZE=2048
        fi
        if [ $MYSQL_LOG_SIZE -lt 32 ]
        then
            MYSQL_LOG_SIZE=32
        fi

        # Export the values of the six variables
        export CPU_CORES=$CPU_CORES
        export REDIS_MEM=$REDIS_MEM
        export MYSQL_MEM=$MYSQL_MEM
        export PHP_MEM=$PHP_MEM
        export MYSQL_POOL_COUNT=$MYSQL_POOL_COUNT
        export PHP_POOL_COUNT=$PHP_POOL_COUNT
        export MYSQL_LOG_SIZE=$MYSQL_LOG_SIZE

        # Output the values of the six variables
        echo "CPU_CORES: $CPU_CORES"
        echo "REDIS_MEM: $REDIS_MEM MB"
        echo "MYSQL_MEM: $MYSQL_MEM MB"
        echo "PHP_MEM: $PHP_MEM MB"
        echo "MYSQL_POOL_COUNT: $MYSQL_POOL_COUNT"
        echo "PHP_POOL_COUNT: $PHP_POOL_COUNT"
		echo "MYSQL_LOG_SIZE: $MYSQL_LOG_SIZE MB"
	fi
}



# initial run
function update_system
{
    if [ -d /etc/needrestart/conf.d ]; then
        echo 'List Restart services only'
        cat >> /etc/needrestart/conf.d/disable.conf <<END
# Restart services (l)ist only, (i)nteractive or (a)utomatically. 
\$nrconf{restart} = 'l'; 
# Disable hints on pending kernel upgrades. 
\$nrconf{kernelhints} = 0;
END
    fi
	
	DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >/dev/null 2>&1
}


# install percona
function setup_repositories
{
    # percona
	echo "Adding percona repo..."
    curl -sO https://repo.percona.com/apt/percona-release_latest.generic_all.deb
    silent ${APT} -y -f install gnupg2 lsb-release ./percona-release_latest.generic_all.deb
	
	# ols
	echo "Adding ols repo..."
	sudo wget -q -O - https://repo.litespeed.sh | sudo bash >/dev/null 2>&1
	
	# Add ondrej/php PPA for PHP packages, if not added already
	echo "Adding php repo..."
    if ! grep ^ /etc/apt/sources.list /etc/apt/sources.list.d/* | grep -q "ondrej/php"; then
        echo "Adding ondrej/php PPA for PHP packages..."
        add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
        apt-get update -qq 
    else
        echo "ondrej/php PPA for PHP packages already exists, skipping..."
    fi

    # update
    silent DEBIAN_FRONTEND=noninteractive apt-get update
    silent DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >/dev/null 2>&1
}


# function to setup firewall
function setup_firewall
{

	# reinstall and reset firewall
	iptables --flush
	iptables --delete-chain
	   
	# Check if ufw is already installed, and only reinstall if not
	if ! command -v ufw &> /dev/null; then
		apt install -y ufw
		echo "y" | ufw reset
	fi

	# default policy
	ufw default deny incoming
	ufw default allow outgoing
	ufw default allow routed

	# open or block ports: 
	ufw allow 22/tcp     # ssh default
	ufw allow 999/tcp    # ssh custom
	ufw allow 123/udp    # ntp
	ufw allow 51820/udp  # wg
	ufw allow 80/tcp     # http
	ufw allow 443/tcp    # https
	ufw allow 443/udp    # http3
	ufw allow 7080/tcp   # ols

	# save and enable
	echo "y" | ufw enable
	ufw status verbose

}


# function to check the basic server configs
function setup_basic
{
    # Basic settings
    dpkg-reconfigure -f noninteractive tzdata
    locale-gen en_US en_US.utf8
    localectl set-locale LANG=en_US.utf8
    update-locale LC_ALL=en_US.utf8
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
	  sudo fallocate -l 2G /swapfile
	  sudo chmod 600 /swapfile
	  sudo mkswap /swapfile
	  sudo swapon /swapfile
	  # Update /etc/fstab to reflect the new size
	  sudo bash -c 'echo "/swapfile swap swap defaults 0 0" >> /etc/fstab'
	else
	  # Check if swap is enabled
	  if grep -q "swapfile" /proc/swaps; then
		# Check the current swap size
		swap_size=$(swapon --bytes --show=SIZE --noheadings)
		swap_size_gb=$(echo $swap_size | awk '{ foo = $1 / 1024 / 1024 / 1024; print foo }')
		
		# If the swap size is not 2GB
		if [ $swap_size_gb -ne 2 ]; then
		  # Resize the swap to 2GB
		  echo "Resizing swap to 2GB..."
		  sudo swapoff -a
		  sudo dd if=/dev/zero of=/swapfile bs=1G count=2
		  sudo chmod 600 /swapfile
		  sudo mkswap /swapfile
		  sudo swapon /swapfile
		  # Update /etc/fstab to reflect the new size
		  sudo bash -c 'sed -i "/swapfile/c\\/swapfile swap swap defaults 0 0" /etc/fstab'
		fi
	  else
		# Create a new permanent swap of 2GB
		echo "Creating a new permanent swap of 2GB..."
		sudo fallocate -l 2G /swapfile
		sudo chmod 600 /swapfile
		sudo mkswap /swapfile
		sudo swapon /swapfile
		# Update /etc/fstab to reflect the new size
		sudo bash -c 'echo "/swapfile swap swap defaults 0 0" >> /etc/fstab'
	  fi
	fi


    # Set up idempotency for limits.conf and fstab
    sed -i '/^#/d;/^$/d' /etc/security/limits.conf
    sed -i '/^#/d;/^$/d' /etc/fstab
}


# install packages
function setup_packages
{

	# basic
	echo "Installing basic packages..."
	DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::="--force-confdef" certbot pv pigz curl wget zip memcached redis-server

	# ols
	echo "Installing OLS..."
	DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::="--force-confdef" openlitespeed lsphp80 lsphp80-common lsphp80-curl


	# php
	echo "Installing PHP FPM..."
	echo "Collecting available packages for all PHP versions..."
	all_packages=""
	for version in 7.4 8.0 8.1 8.2; do
	  available_packages=""
	  for package in php${version}-fpm php${version}-cli php${version}-bcmath php${version}-common php${version}-curl php${version}-gd php${version}-gmp php${version}-imap php${version}-intl php${version}-mbstring php${version}-mysql php${version}-pgsql php${version}-soap php${version}-tidy php${version}-xml php${version}-xmlrpc php${version}-zip php${version}-opcache php${version}-xsl php${version}-imagick php${version}-redis php${version}-memcached; do
		if apt-cache show $package > /dev/null 2>&1; then
		  available_packages="$available_packages $package"
		else
		  echo "$package does not exist, skipping..."
		fi
	  done
	  if [[ ! -z $available_packages ]]; then
		all_packages="$all_packages $available_packages"
	  fi
	done

	if [[ ! -z $all_packages ]]; then
	  echo "The following packages are available for all PHP versions: $all_packages"
	  echo "Installing all available packages..."
	  DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::="--force-confdef" $all_packages
	else
	  echo "No packages available for any PHP version."
	fi



	# wp cli
	echo "Installing wp-cli..."
	if ! command -v wp &> /dev/null; then INSTALLED_VERSION="0.0.0"; else INSTALLED_VERSION=$(wp --version --allow-root | awk '{print $2}'); fi
	LATEST_VERSION=$(curl -s https://api.github.com/repos/wp-cli/wp-cli/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
	if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
	  curl -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
	  chmod +x wp-cli.phar
	  mv wp-cli.phar /usr/local/bin/wp	  
	  [ ! -f /usr/bin/wp ] && sudo ln -s /usr/local/bin/wp /usr/bin/wp
	  echo "Updated wp from version $INSTALLED_VERSION to $LATEST_VERSION"
	else
	  echo "wp is already up-to-date at version $INSTALLED_VERSION"
	fi
	
	# postfix
	echo "Installing Postfix..."
	debconf-set-selections <<< "postfix postfix/mailname string localhost"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
	apt-get install -y -o Dpkg::Options::="--force-confdef" ssl-cert
	apt-get install -y -o Dpkg::Options::="--force-confdef" postfix
	apt-get install -y -o Dpkg::Options::="--force-confdef" mailutils
	
	# percona
	echo "Installing Percona..."
	percona-release setup ps80 > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get -y -f --allow-unauthenticated install percona-server percona-server-server > /dev/null 2>&1
    service mysql start

}


# create self signed ssl for ols
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
	
    
    cat << EOF > $CSR
[req]
prompt=no
distinguished_name=openlitespeed
[openlitespeed]
commonName = ${COMMNAME}
countryName = ${SSL_COUNTRY}
localityName = ${SSL_LOCALITY}
organizationName = ${SSL_ORG}
organizationalUnitName = ${SSL_ORGUNIT}
stateOrProvinceName = ${SSL_STATE}
emailAddress = ${SSL_EMAIL}
name = openlitespeed
initials = CP
dnQualifier = openlitespeed
[server_exts]
extendedKeyUsage=1.3.6.1.5.5.7.3.1
EOF
    openssl req -x509 -config $CSR -extensions 'server_exts' -nodes -days 820 -newkey rsa:2048 -keyout ${KEY} -out ${CERT} >/dev/null 2>&1
    rm -f $CSR
    
    mv ${KEY}  /usr/local/lsws/conf/$KEY
    mv ${CERT} /usr/local/lsws/conf/$CERT
    chmod 0600 /usr/local/lsws/conf/$KEY
    chmod 0600 /usr/local/lsws/conf/$CERT
}


# download configs
function setup_configs
{
	
	# download sshd_config
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/sshd/sshd_config > /tmp/sshd_config
	cat /tmp/sshd_config | grep -q "ListenAddress" && cp /tmp/sshd_config /etc/ssh/sshd_config && echo "sshd_config updated." || echo "Error downloading sshd_config ..."
	rm /tmp/sshd_config
	service sshd restart
	
	# Download php.ini file
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/php/php.ini > /tmp/php.ini
	if cat /tmp/php.ini | grep -q "max_input_vars"; then find /etc/php -type f -iname php.ini -exec cp /tmp/php.ini {} \; && echo "php.ini files updated."; else echo "Error downloading php.ini ..."; fi
	rm /tmp/php.ini
	for version in 7.4 8.0 8.1 8.2; do systemctl restart php${version}-fpm; done

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
	sed -i "s/^innodb_buffer_pool_instances.*$/innodb_buffer_pool_instances $PHP_POOL_COUNT/" /etc/mysql/my.cnf
	sed -i "s/^innodb_buffer_pool_size.*$/innodb_buffer_pool_size ${MYSQL_MEM}M/" /etc/mysql/my.cnf
	sed -i "s/^innodb_log_file_size.*$/innodb_log_file_size $MYSQL_LOG_SIZE/" /etc/mysql/my.cnf
	systemctl restart mysql
	
	# redis
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/redis/redis.conf > /tmp/redis.conf
	cat /tmp/redis.conf | grep -q "maxmemory" && cp /tmp/redis.conf /etc/redis/redis.conf && echo "redis.conf updated." || echo "Error downloading redis.conf ..."
	rm /tmp/redis.conf
	service redis-server restart
	
	# download postfix	
	curl -skL https://raw.githubusercontent.com/peixotorms/ols1clk/master/configs/postfix/main.cf > /tmp/main.cf
	cat /tmp/main.cf | grep -q "smtpd_banner" && cp /tmp/main.cf /etc/postfix/main.cf && echo "main.cf updated." || echo "Error downloading main.cf ..."
	rm /tmp/main.cf
	echo 'postmaster: /dev/null\nroot: /dev/null' | sudo tee /etc/aliases > /dev/null
	systemctl restart postfix
	
}



# install
update_system
calculate_memory
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
