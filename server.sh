#!/bin/bash

##############################################################################
#		OpenLiteSpeed, LetsEncrypt                                           #
#       PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI                       #
#       Percona Server 8.0 for MySQL, Postfix and Redis                      #
#		Author: Raul Peixoto, WP Raiser										 #
##############################################################################

# import common functions
source <(curl -sSf https://raw.githubusercontent.com/peixotorms/ols/main/inc/common.sh)

# runtime defaults
CONFIRM_SETUP="0"
RESTART_SSH="0"
CURSSHPORT=$(calculate_memory_configs "CURSSHPORT")
SSH_PORT="22"
OLS_PORT="7080"
OLS_USER="olsadmin"
OLS_PASS=$(gen_rand_pass)
FUNC_NAMES="update_system, update_limits, setup_sshd, setup_repositories, setup_firewall, install_basic_packages, install_ols, install_wp_cli, install_percona, install_redis, install_postfix"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h | --help ) # Print usage instructions
            echo ""
            printf "Usage: bash [--functions <function_names>] [-u | --ols_user <username>] [-p | --ols_pass <password>] [-v | --verbose] [-h | --help]\n"
            echo ""
            printf "Options:\n"
            printf "%-4s%-11s%-49s\n" "" "-f | --functions" "Run a comma-separated list of function names:"
            IFS=',' read -ra FUNC_NAMES <<< "update_system, update_limits, setup_sshd, setup_repositories, setup_firewall, install_basic_packages, install_ols, install_php, install_wp_cli, install_percona, install_redis, install_postfix"
            for FUNC_NAME in "${FUNC_NAMES[@]}"; do
                printf "%-15s%-48s\n" "" "$FUNC_NAME"
            done
            printf "%-4s%-11s%-49s\n" "" "--ols_user" "Customize OpenLiteSpeed username"
            printf "%-4s%-11s%-49s\n" "" "--ols_pass" "Customize OpenLiteSpeed password"
			printf "%-4s%-11s%-49s\n" "" "--ols_port" "Customize OpenLiteSpeed port"
            printf "%-4s%-11s%-49s\n" "" "--verbose | -v" "Enable verbose mode"
            printf "%-4s%-11s%-49s\n" "" "--help | -h" "Show this help message"
            echo ""
            printf "Examples:\n"
            printf "%-4s%-11s%-49s\n" "" "bash server.sh -f install_ols,install_php"
            printf "%-4s%-11s%-49s\n" "" "bash server.sh -f install_ols,install_php -u myusername -p mypassword"
            echo ""
            exit 0
            ;;
		--functions | -f )
			# Get the function names from the --functions flag
			IFS=', ' read -ra REQUESTED_NAMES <<< "$2"
			
			# Only filter and merge function names if --functions is not empty
			if [[ ${#REQUESTED_NAMES[@]} -gt 0 ]]; then
				# Initialize names arrays
				NAMES=()
				DEFAULT_NAMES=()
				
				# Filter requested function names and default function names
				for func_name in ${FUNC_NAMES//,/ }; do
					found=false
					for name in "${REQUESTED_NAMES[@]}"; do
						if [[ "$name" == "$func_name" ]]; then
							NAMES+=("$func_name")
							found=true
							break
						fi
					done
					if ! $found; then
						DEFAULT_NAMES+=("$func_name")
					fi
				done
				
				# Use the requested function names if any, otherwise use the default names
				if [[ ${#NAMES[@]} -gt 0 ]]; then
					FUNC_NAMES="$(IFS=','; echo "${NAMES[*]}")"
				else
					FUNC_NAMES="$(IFS=','; echo "${DEFAULT_NAMES[*]}")"
				fi
			fi

			shift
			shift
			;;
        --ols_user ) # Set OLS_USER
            if [[ "$2" =~ ^[[:alnum:]]{8,32}$ ]]; then
                OLS_USER="$2"
            else
                print_colored red "Error:" "OLS_USER must be between 8-32 alphanumeric characters."
                exit 1
            fi
            shift
            shift
            ;;
       --ols_pass ) # Set OLS_PASS
			if [[ "$2" =~ [0-9] ]] && [[ "$2" =~ [a-zA-Z] ]] && [[ "$2" =~ [,+=\-_!@] ]] && [[ ${#2} -ge 8 ]] && [[ ${#2} -le 32 ]] && [[ ! "$2" =~ [[:space:]] ]]; then
				OLS_PASS="$2"
			else
				print_colored red "Error:" "--ols_pass must be between 8-32 chars and include at least a digit, a letter and one of the following symbols: ,+=-_!@"
				exit 1
			fi
			shift
			shift
			;;
		--ols_port ) # Set OLS_PORT
            if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 65535 ]; then
                OLS_PORT="$2"
            else
                print_colored red "Error:" "Invalid --ols_port $2."
				exit 1
            fi
            shift
            shift
            ;;
		--ssh_port ) # Set OLS_PORT
            if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 65535 ]; then
                SSH_PORT="$2"
            else
                print_colored red "Error:" "Invalid --ssh_port $2."
				exit 1
            fi
            shift
            shift
            ;;
        --verbose | -v ) # Enable verbose mode
            VERBOSE=1
            shift
            ;;
        * ) # Invalid option
            print_colored red "Error:" "Invalid option: $1"
            exit 1
            ;;
    esac
done


# START FUNCTIONS


# This function updates the system and disables hints on pending kernel upgrades
function update_limits
{
		
	# basic settings
	echo 'Adjusting time to UTC and locale to en_US...'
	silent dpkg-reconfigure -f noninteractive tzdata
	silent locale-gen en_US en_US.utf8
	silent localectl set-locale LANG=en_US.utf8
	silent update-locale LC_ALL=en_US.utf8
	
	echo 'Setting nano as default editor...'
	echo "SELECTED_EDITOR=\"/bin/nano\"" > /root/.selected_editor
	
	echo 'Setting localhost ip address...'
	grep -qxF '127.0.0.1 localhost' /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
	
	echo 'Increasing unix socket limits...'
	silent ulimit -n 65000
	grep -qxF "* soft nofile 65000" /etc/security/limits.conf || echo "* soft nofile 65000" >> /etc/security/limits.conf
	grep -qxF "* hard nofile 65000" /etc/security/limits.conf || echo "* hard nofile 65000" >> /etc/security/limits.conf
	echo "net.core.somaxconn = 65000" | tee /etc/sysctl.d/99-somaxconn.conf >/dev/null && silent sysctl --system
	
	echo "Increasing network buffer size..."
	echo "net.ipv4.tcp_rmem = 4096 4194304 33554432" > /etc/sysctl.d/99-tcp_mem.conf
	echo "net.ipv4.tcp_wmem = 4096 4194304 33554432" >> /etc/sysctl.d/99-tcp_mem.conf
	silent sysctl --system

	# adjust swap to 2GB
	# Get current swap size in gigabytes
	current_swap_size_gb=$(free --giga | awk '/Swap/ {print $2}')

	# Target swap size in gigabytes (2G)
	target_swap_size_gb=2

	# Check if current swap size is not 2G
	echo "Adjusting swap file..."
	if [ "${current_swap_size_gb%.*}" -ne "$target_swap_size_gb" ]; then
		swapoff -a
		[ -f /swapfile ] && rm /swapfile
		silent fallocate -l 2G /swapfile
		chmod 600 /swapfile
		silent mkswap /swapfile
		silent swapon /swapfile

		# Update /etc/fstab to persist swap across reboots
		grep -v '/swapfile' /etc/fstab > /tmp/fstab_no_swap
		echo '/swapfile none swap sw 0 0' >> /tmp/fstab_no_swap
		mv /tmp/fstab_no_swap /etc/fstab
		print_colored green "Success:" "Swap file adjusted to 2G."
	else
		print_colored cyan "Notice:" "The current swap size is already 2GB."
	fi

	
}



# This function downloads and updates configuration files for sshd
function setup_sshd
{
	
	# download sshd_config
	echo "Updating sshd_config... "
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/sshd/sshd_config > /tmp/sshd_config
	cat /tmp/sshd_config | grep -q "ListenAddress" && cp /tmp/sshd_config /etc/ssh/sshd_config && print_colored green "Success:" "sshd_config updated." || print_colored red "Error:" "downloading sshd_config ..."
	rm /tmp/sshd_config
	[[ "${SSH_PORT}" != "22" ]] && sed -i "s/^Port 22.*$/Port ${SSH_PORT}/" /etc/ssh/sshd_config
	[[ "${SSH_PORT}" != "${CURSSHPORT}" ]] && print_colored magenta "Warning:" "SSH port changed from ${CURSSHPORT} to $SSH_PORT."

}


# This function sets up the necessary repositories for Percona, OpenLiteSpeed and PHP
function setup_repositories
{
	# percona
	echo "Adding Percona repositories..."
	silent curl -s https://repo.percona.com/apt/percona-release_latest.generic_all.deb -o /tmp/percona-release_latest.generic_all.deb
	silent apt-get -y -f install gnupg2 lsb-release 
	silent dpkg -i /tmp/percona-release_latest.generic_all.deb
	rm /tmp/percona-release_latest.generic_all.deb
	
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
	silent iptables -P INPUT ACCEPT
	silent iptables -P FORWARD ACCEPT
	silent iptables -P OUTPUT ACCEPT
	silent iptables -F
	silent iptables -X
	silent iptables -Z

	# Check if ufw is already installed, and only reinstall if not
	if ! command -v ufw &> /dev/null; then
		DEBIAN_FRONTEND=noninteractive silent apt install -y ufw
	fi
	
	# reset
	echo "y" | ufw reset > /dev/null

	# default policy
	silent ufw default deny incoming
	silent ufw default allow outgoing
	silent ufw default allow routed

	# open or block ports: 
	silent ufw allow ${SSH_PORT}/tcp     # ssh
	silent ufw allow 123/udp	         # ntp
	silent ufw allow 51820/udp	         # wireguard
	silent ufw allow 80/tcp		         # http
	silent ufw allow 443/tcp	         # https
	silent ufw allow 443/udp	         # http3
	silent ufw allow ${OLS_PORT}/tcp	 # ols

	# save and enable
	echo "y" | silent ufw enable
	# ufw status verbose

}


# Basic packages: certbot, pv, pigz, curl, wget, zip, memcached, etc
function install_basic_packages() {
	DEBIAN_FRONTEND=noninteractive silent apt install -y -o Dpkg::Options::="--force-confdef" certbot pv pigz curl wget zip net-tools traceroute memcached
}


# OpenLiteSpeed web server and its PHP 8 packages.
function install_ols() {

	# start
	echo "Installing OpenLiteSpeed... "

	# packages
	all_packages=""
	for version in 74 80 81 82; do
		available_packages="openlitespeed"
		for package in lsphp${version} lsphp${version}-mysql lsphp${version}-imap lsphp${version}-curl lsphp${version}-common lsphp${version}-json lsphp${version}-imagick lsphp${version}-opcache lsphp${version}-redis lsphp${version}-memcached lsphp${version}-intl; do
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
		print_colored red "Error:" "No packages available for any LSPHP version."
	fi
	
	# Set admin credentials
	if [ $? = 0 ] ; then
		[ -z "$OLS_USER" ] && OLS_USER="admin"
		[ -z "$OLS_PASS" ] && OLS_PASS=$(gen_rand_pass)
		ENCRYPT_PASS=`"/usr/local/lsws/admin/fcgi-bin/admin_php" -q "/usr/local/lsws/admin/misc/htpasswd.php" $OLS_PASS`
		if [ $? = 0 ] ; then
			echo "${OLS_USER}:$ENCRYPT_PASS" > "/usr/local/lsws/admin/conf/htpasswd"
			if [ $? = 0 ] ; then
				echo $OLS_PASS > /usr/local/lsws/password.user
			fi
		fi
	fi
	
	# change default port
    if [ -e /usr/local/lsws/admin/conf/admin_config.conf ]; then 
		sed -i "s/^.*address .*$/  address               *:${OLS_PORT}/g" /usr/local/lsws/admin/conf/admin_config.conf
		print_colored magenta "Warning:" "OLS port set to ${OLS_PORT}"
	else
		print_colored red "Error:" "/usr/local/lsws/admin/conf/admin_config.conf not found."
	fi
	
	# download ols config
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/ols/httpd_config.conf > /tmp/httpd_config.conf
	cat /tmp/httpd_config.conf | grep -q "autoLoadHtaccess" && cp /tmp/httpd_config.conf /usr/local/lsws/conf/httpd_config.conf && print_colored green "Success:" "httpd_config.conf updated." || print_colored red "Error:" "downloading httpd_config.conf ..."
	rm /tmp/httpd_config.conf
	
	# set lsphp pool concurrency limit
	# allow 1 instance per cpu core + 3 connections per instance
	# more instances avoid contention on CPU-bound sites (PHP), while maxConns is better for I/O-bound sites (mysql, disk)
	CPU_CORES=$(calculate_memory_configs "CPU_CORES")
	PHP_BACKLOG=$(calculate_memory_configs "PHP_BACKLOG")
	sed -i "s/^.*instances .*$/  instances               ${CPU_CORES}/g" /usr/local/lsws/conf/httpd_config.conf
	sed -i "s/^.*maxConns .*$/  maxConns                3/g" /usr/local/lsws/conf/httpd_config.conf
	sed -i "s/^.* PHP_LSAPI_CHILDREN.*$/  env                     PHP_LSAPI_CHILDREN=3/g" /usr/local/lsws/conf/httpd_config.conf
	sed -i "s/^.*backlog .*$/  backlog                 ${PHP_BACKLOG}/g" /usr/local/lsws/conf/httpd_config.conf
	
	# configure
	# Download php.ini file
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/php/php.ini > /tmp/php.ini
	if cat /tmp/php.ini | grep -q "max_input_vars"; then find /usr/local/lsws -type f -iname php.ini -exec cp /tmp/php.ini {} \; && print_colored green "Success:" "lsapi php.ini files updated."; else print_colored red "Error:" "downloading php.ini ..."; fi
	rm /tmp/php.ini
	
	# permissions
	chown -R lsadm:lsadm /usr/local/lsws	
	
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
	
	# restart
	killall -9 lsphp || echo "PHP process was not running."
	systemctl restart lshttpd
	
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
		print_colored red "Error:" "No packages available for any PHP version."
	fi
	
	# enable
	phpenmod -v 8.2 -s cli bcmath curl gd gmp imap intl mbstring pgsql soap tidy xml xmlrpc zip opcache xsl imagick redis memcached

	
	# configure
	# Download php.ini file
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/php/php.ini > /tmp/php.ini
	if cat /tmp/php.ini | grep -q "max_input_vars"; then find /etc/php -type f -iname php.ini -exec cp /tmp/php.ini {} \; && print_colored green "Success:" "php.ini files updated."; else print_colored red "Error:" "downloading php.ini ..."; fi
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
	if cat /tmp/php-fpm.conf | grep -q "error_log"; then find /etc/php -type f -iname php-fpm.conf -exec cp /tmp/php-fpm.conf {} \; && print_colored green "Success:" "php-fpm.conf file updated."; else print_colored red "Error:" "downloading php-fpm.conf ..."; fi
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
		echo "Updated wp to $LATEST_VERSION"
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
	cat /tmp/my.cnf | grep -q "mysqld" && cp /tmp/my.cnf /etc/mysql/my.cnf && print_colored green "Success:" "my.cnf updated." || print_colored red "Error:" "downloading my.cnf ..."
	rm /tmp/my.cnf
	MYSQL_MEM=$(calculate_memory_configs "MYSQL_MEM")
	MYSQL_POOL_COUNT=$(calculate_memory_configs "MYSQL_POOL_COUNT")
	MYSQL_LOG_SIZE=$(calculate_memory_configs "MYSQL_LOG_SIZE")	
	sed -i "s/^innodb_buffer_pool_instances.*$/innodb_buffer_pool_instances	 = $MYSQL_POOL_COUNT/" /etc/mysql/my.cnf
	sed -i "s/^innodb_buffer_pool_size.*$/innodb_buffer_pool_size				= ${MYSQL_MEM}M/" /etc/mysql/my.cnf
	sed -i "s/^innodb_log_file_size.*$/innodb_log_file_size					 = ${MYSQL_LOG_SIZE}M/" /etc/mysql/my.cnf
	systemctl restart mysql	
	
	# Stop MySQL service
	systemctl stop mysql
	
	# Create the directory for the UNIX socket file, if it doesn't exist
	mkdir -p /var/run/mysqld
	chown mysql:mysql /var/run/mysqld
	
	# Start MySQL with --skip-grant-tables and --skip-networking
	silent mysqld_safe --skip-grant-tables --skip-networking &
	
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
	cat /tmp/redis.conf | grep -q "maxmemory" && cp /tmp/redis.conf /etc/redis/redis.conf && print_colored green "Success:" "redis.conf updated." || print_colored red "Error:" "downloading redis.conf ..."
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
	cat /tmp/main.cf | grep -q "smtpd_banner" && cp /tmp/main.cf /etc/postfix/main.cf && print_colored green "Success:" "main.cf updated." || print_colored red "Error:" "downloading main.cf ..."
	rm /tmp/main.cf
	echo 'postmaster: /dev/null\nroot: /dev/null' | sudo tee /etc/aliases > /dev/null
	systemctl restart postfix
	
}


function before_install_display
{	
	# info
	IP=$(calculate_memory_configs "IP")
	CPU_CORES=$(calculate_memory_configs "CPU_CORES")
	TOTAL_RAM=$(calculate_memory_configs "TOTAL_RAM")
	MYSQL_MEM=$(calculate_memory_configs "MYSQL_MEM")
	DISK_AVAILABLE=$(calculate_memory_configs "DISK_AVAILABLE")
	MYSQL_POOL_COUNT=$(calculate_memory_configs "MYSQL_POOL_COUNT")
	MYSQL_LOG_SIZE=$(calculate_memory_configs "MYSQL_LOG_SIZE")
	REDIS_MEM=$(calculate_memory_configs "REDIS_MEM")
	PHP_MEM=$(calculate_memory_configs "PHP_MEM")	
	PHP_POOL_COUNT=$(calculate_memory_configs "PHP_POOL_COUNT")	
	LSPHP_POOL_COUNT=$(calculate_memory_configs "LSPHP_POOL_COUNT")
	
	echo ""
	print_chars 60 -
    print_colored cyan   "Server capabilities: "
    print_colored yellow "Public IP:           " "$IP"
    print_colored yellow "CPU cores:           " "$CPU_CORES"
    print_colored yellow "RAM Size:            " "${TOTAL_RAM}M"
	print_colored yellow "Disk Available:      " "$DISK_AVAILABLE"
	echo ""
	
	# with info
	for FUNCTION_NAME in $(echo "$FUNC_NAMES" | tr ',' '\n' | uniq); do
		
		if [[ "$FUNCTION_NAME" = "setup_sshd" ]]; then
			echo ""
			print_colored white  "Task:                " "Reset ssh server settings!"
			print_colored yellow "SSH Port:            " "$SSH_PORT"
			echo ""
		fi
		
		if [[ "$FUNCTION_NAME" = "install_ols" ]]; then
			echo ""
			print_colored white  "Task:                " "Install and reset Openlitespeed!"
			print_colored yellow "OLS URL:             " "https://${IP}:$OLS_PORT"
			print_colored yellow "OLS username:        " "$OLS_USER"
			print_colored yellow "OLS password:        " "$OLS_PASS"
			echo ""
		fi
		
		if [[ "$FUNCTION_NAME" = "install_percona" ]]; then
			echo ""
			print_colored white  "Task:                " "Install and reset Percona Server for MySQL!"
			print_colored yellow "DB version:          " "8.0"
			print_colored yellow "DB auth:             " "root user using 'auth_socket' plugin"
			print_colored yellow "InnoDB Pool Size:    " "${MYSQL_MEM}M"
			print_colored yellow "InnoDB Pool Count:   " "$MYSQL_POOL_COUNT"
			echo ""
		fi
		
		if [[ "$FUNCTION_NAME" = "install_php" ]]; then
			echo ""
			print_colored white  "Task:                " "Install and reset PHP!"
			print_colored yellow "FPM Versions:        " "7.4, 8.0, 8.1 and 8.2"
			print_colored yellow "PHP Workers:         " "$PHP_POOL_COUNT"
			print_colored yellow "OPCache:             " "256M"
			echo ""
		fi
		
		if [[ "$FUNCTION_NAME" = "install_redis" ]]; then
			echo ""
			print_colored white  "Task:                " "Install and reset Redis!"
			print_colored yellow "Memory:              " "${REDIS_MEM}M (allkeys-lru)"
			echo ""
		fi
		
	done
	
	# tasks only
	for FUNCTION_NAME in $(echo "$FUNC_NAMES" | tr ',' '\n' | uniq); do
						
		if [[ "$FUNCTION_NAME" = "update_system" ]]; then
			print_colored white  "Task:                " "Install updates!"
		fi
		
		if [[ "$FUNCTION_NAME" = "update_limits" ]]; then
			print_colored white  "Task:                " "Update swap and other limits!"
		fi
				
		if [[ "$FUNCTION_NAME" = "setup_firewall" ]]; then
			print_colored white  "Task:                " "Install and reset firewall!"
		fi
		
		if [[ "$FUNCTION_NAME" = "install_basic_packages" ]]; then
			print_colored white  "Task:                " "Process basic packages!"
		fi
		
		if [[ "$FUNCTION_NAME" = "install_wp_cli" ]]; then
			print_colored white  "Task:                " "Install wp-cli!"
		fi
				
		if [[ "$FUNCTION_NAME" = "install_postfix" ]]; then
			print_colored white  "Task:                " "Install and reset Postfix!"
			echo ""
		fi
		
	done
	
	print_chars 60 -
	echo ""	
	
}



# END FUNCTIONS




# display summary and ask permission
echo ""
before_install_display

# confirmation request
printf 'Are these settings correct? Type n to quit, otherwise will continue. [Y/n]  '
read answer
if [ "$answer" = "N" ] || [ "$answer" = "n" ] ; then
    print_colored red "Error:" "Aborting installation!"
    exit 0
else
	CONFIRM_SETUP="1"
	echo ""
fi
	
print_colored cyan "Notice:" "Starting installation >> >> >> >> >> >> >>"
echo ""

# install
if [ "$CONFIRM_SETUP" != "0" ] ; then
	for FUNCTION_NAME in $(echo "$FUNC_NAMES" | tr ',' '\n' | uniq); do
		echo "Running function: $FUNCTION_NAME"
		"$FUNCTION_NAME"
		
		# sshd restart warning?
		if [[ "$FUNCTION_NAME" = "setup_sshd" && "${SSH_PORT}" != "${CURSSHPORT}" ]]; then
			RESTART_SSH="1"
		else
			service sshd restart
		fi

		
	done
fi 

# restart sshd after port change, after everything else
if [ "$RESTART_SSH" != "0" ] ; then
	print_colored magenta "Warning:" "Please re-login using port $SSH_PORT"
	service sshd restart
	exit 0
fi 

# finish
print_colored cyan "Notice:" "Installation complete!"

