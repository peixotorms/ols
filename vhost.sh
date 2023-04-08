#!/bin/bash

##############################################################################
#		OpenLiteSpeed, LetsEncrypt                                           #
#       PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI                       #
#       Percona Server 8.0 for MySQL, Postfix and Redis                      #
#		Author: Raul Peixoto, WP Raiser										 #
##############################################################################

# import common functions
source <(curl -sSf https://raw.githubusercontent.com/peixotorms/ols/main/inc/common.sh)


# Parse command-line arguments
TEMP=$(getopt -o 'h' --long help,domain:,aliases:,ssl:,php:,path:,sftp_user:,sftp_pass:,db_host:,db_port:,db_user:,db_pass:,wp_install:,wp_user:,wp_pass:,dev_mode: -n "$(basename -- "$0")" -- "$@")
eval set -- "$TEMP"
while true; do
    case "$1" in
        -h|--help)
			echo ""
			printf "Usage: bash $(basename -- "$0") --domain <domain_name> [OPTIONS]\n"
			echo ""
			printf "Options:\n"
			printf "%-4s%-25s%-52s\n" "" "--domain (required)" "Domain name to set up"
			printf "%-4s%-25s%-52s\n" "" "--aliases" "Comma-separated list of domain aliases"
			printf "%-4s%-25s%-52s\n" "" "--ssl" "Enable or disable SSL. Default is 'yes'"
			printf "%-4s%-25s%-52s\n" "" "--php" "PHP version to install. Must be 7.4, 8.0, 8.1, or 8.2. Default is '8.0'"
			printf "%-4s%-25s%-52s\n" "" "--vpath" "Path to install website. Default is '/home/sites/<domain_name>'"
			printf "%-4s%-25s%-52s\n" "" "--sftp_user" "SFTP username. Default is generated from domain name"
			printf "%-4s%-25s%-52s\n" "" "--sftp_pass" "SFTP password. Default is random"
			printf "%-4s%-25s%-52s\n" "" "--db_host" "Database host. Default is 'localhost'"
			printf "%-4s%-25s%-52s\n" "" "--db_port" "Database port. Default is '3306'"
			printf "%-4s%-25s%-52s\n" "" "--db_user" "Database username. Default is generated from domain name"
			printf "%-4s%-25s%-52s\n" "" "--db_pass" "Database password. Default is random"
			printf "%-4s%-25s%-52s\n" "" "--wp_install" "Install WordPress or not. Default is 'yes'"
			printf "%-4s%-25s%-52s\n" "" "--wp_user" "WordPress username. Default is generated from domain name"
			printf "%-4s%-25s%-52s\n" "" "--wp_pass" "WordPress password. Default is random"
			printf "%-4s%-25s%-52s\n" "" "--dev_mode" "Enable or disable developer mode. Default is 'yes'"
			printf "%-4s%-25s%-52s\n" "" "--help, -h" "Show this help message"
			echo ""
			printf "Examples:\n"
			printf "%-4s%-25s%-52s\n" "" "bash $(basename -- "$0") --domain example.com --ssl no --php 7.4"
			printf "%-4s%-25s%-52s\n" "" "bash $(basename -- "$0") --domain example.com --aliases example.net,example.org"
			echo ""
			exit 0
            ;;
        --domain)
            domain="${2}"; shift 2
            if ! validate_domain "$domain"; then
                print_colored red "Invalid domain name $domain"; exit 1
            fi
			
			# Create new variable without www subdomain
            domain_no_www="${domain/www.}"

            # Set default values based on domain
            vpath="/home/sites/$domain_no_www"
            sftp_user="$(generate_user_name "$domain_no_www")"
            db_user="$(generate_user_name "$domain_no_www")"
            wp_user="$(generate_user_name "$domain_no_www")"
			
            # Set default passwords
            sftp_pass="$(gen_rand_pass)"
            db_pass="$(gen_rand_pass)"
            wp_pass="$(gen_rand_pass)"
			
			# Initialize default values
			ssl="yes"
			php="8.0"
			db_host="localhost"
			db_port="3306"
			wp_install="yes"
			dev_mode="yes"
			aliases=""
			
            ;;
        --aliases)
			# Check if the input string is a comma-separated list of valid domain names.
			if [[ "${2:-}" =~ ^([^,]+,)*[^,]+$ ]]; then
				# The input string is valid, so assign it to the aliases variable.
				aliases="${2}"; shift 2
				# Split the comma-separated string into an array
				IFS=',' read -ra alias_list <<< "$aliases"
				# Strip leading and trailing whitespace from each alias domain
				alias_list=( "${alias_list[@]// /}" )
				# Check each alias domain using the validate_domain function
				for alias in "${alias_list[@]}"; do
					if ! validate_domain "$alias"; then
						print_colored red "Invalid alias domain: $alias"; exit 1
					fi
				done
				# Ensure that $domain is not in the alias_list array
				if [[ " ${alias_list[@]} " =~ " $domain " ]]; then
					print_colored red "Domain name cannot be an alias: $domain"; exit 1
				fi
				# Overwrite the aliases variable with the imploded alias_list, separated with comma
				aliases="$(IFS=','; echo "${alias_list[*]}")"
			else
				# The input string is invalid, so print an error message and exit.
				print_colored red "Invalid aliases: ${2:-}"; exit 1
			fi
			;;
        --ssl)
            case "${2,,}" in
                yes|no)
                    ssl="${2,,}"; shift 2
                    ;;
                *)
                    print_colored red "Invalid SSL value: $2. Must be 'yes' or 'no'."; exit 1
                    ;;
            esac
            ;;
        --php)
            case "${2,,}" in
                7.4|8.0|8.1|8.2)
                    php="${2,,}"; shift 2
                    ;;
                *)
                    print_colored red "Invalid PHP version: $2. Must be 7.4, 8.0, 8.1, or 8.2."; exit 1
                    ;;
            esac
            ;;
        --vpath)
            path="${2:-/home/sites/$domain_no_www}"; shift 2
            if [[ "${vpath%/}" != *"/$domain_no_www" ]]; then
                print_colored red "Invalid path: must include domain as the last directory name"; exit 1
            fi
            ;;
        --sftp_user)
            sftp_user="$2"; shift 2
            if [[ -z "$sftp_user" ]]; then
                sftp_user=$(generate_user_name "$domain")
            fi
            ;;
        --sftp_pass)
			sftp_pass="${2:-$(gen_rand_pass)}"
			if [[ "$sftp_pass" =~ [^a-zA-Z0-9,+=@\-_!] ]]; then
				print_colored red "Invalid SFTP password format. Only alphanumeric characters and these special characters are allowed: ,+=@-_!"; exit 1
			elif [[ "${#sftp_pass}" -lt 8 ]] || [[ "${#sftp_pass}" -gt 32 ]]; then
				print_colored red "Invalid SFTP password length. Must be between 8 and 32 characters."; exit 1
			fi
			shift 2
			;;
        --db_host)
            db_host="${2:-localhost}"; shift 2
            ;;
        --db_port)
            db_port="${2:-3306}"; shift 2
            ;;
        --db_user)
            db_user="${2:-$(generate_user_name "$domain_no_www")}"
            if [[ "$db_user" =~ ^[0-9] ]] || [[ "${#db_user}" -lt 3 ]]; then
                db_user="user_$db_user"
            fi
            db_user="$(echo "$db_user" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
            shift 2
            ;;
        --db_pass)
            db_pass="${2:-$(gen_rand_pass)}"
            if [[ "$db_pass" =~ [^a-zA-Z0-9,+=@\-_!] ]]; then
                print_colored red "Invalid database password format. Only alphanumeric characters and these special characters are allowed: ,+=@-_!"; exit 1
            elif [[ "${#db_pass}" -lt 8 ]] || [[ "${#db_pass}" -gt 32 ]]; then
                print_colored red "Invalid database password length. Must be between 8 and 32 characters."; exit 1
            fi
            shift 2
            ;;
        --wp_install)
            case "${2,,}" in
                yes|no)
                    wp_install="${2,,}"; shift 2
                    ;;
                *)
                    print_colored red "Invalid WordPress installation value: $2. Must be 'yes' or 'no'."; exit 1
                    ;;
            esac
            ;;
        --wp_user)
            wp_user="${2:-$(generate_user_name "$domain_no_www")}"
            if [[ "$wp_user" =~ ^[0-9] ]] || [[ "${#wp_user}" -lt 3 ]]; then
                wp_user="user_$wp_user"
            fi
            wp_user="$(echo "$wp_user" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
            shift 2
            ;;
        --wp_pass)
            wp_pass="${2:-$(gen_rand_pass)}"
            if [[ "$wp_pass" =~ [^a-zA-Z0-9,+=@\-_!] ]]; then
                print_colored red "Invalid WordPress password format. Only alphanumeric characters and these special characters are allowed: ,+=@-_!"; exit 1
            elif [[ "${#wp_pass}" -lt 8 ]] || [[ "${#wp_pass}" -gt 32 ]]; then
                print_colored red "Invalid WordPress password length. Must be between 8 and 32 characters."; exit 1
            fi
            shift 2
            ;;
        --dev_mode)
			case "${2,,}" in
				yes|no)
					dev_mode="${2,,}"; shift 2
					;;
				*)
					print_colored red "Invalid dev mode value: $2. Must be 'yes' or 'no'."; exit 1
			esac
			;;
        --)
            shift
            break
            ;;
        *)
            print_colored red "Internal error!"; exit 1
            ;;
    esac
	
	if [[ "$#" == "0" ]]; then
        break
    fi
	
done

# Ensure --domain is mandatory
if [[ -z "$domain" ]]; then
    print_colored red "Error: --domain option is required."; exit 1
fi



# run
print_colored cyan "Starting install..."

printf "%-15s %s\n" "Domain:" "$domain"
printf "%-15s %s\n" "Aliases:" "$aliases"
printf "%-15s %s\n" "SSL:" "$ssl"
printf "%-15s %s\n" "PHP version:" "$php"
printf "%-15s %s\n" "Path:" "${vpath}"
printf "%-15s %s\n" "SFTP user:" "$sftp_user"
printf "%-15s %s\n" "SFTP password:" "$sftp_pass"
printf "%-15s %s\n" "DB host:" "$db_host"
printf "%-15s %s\n" "DB port:" "$db_port"
printf "%-15s %s\n" "DB user:" "$db_user"
printf "%-15s %s\n" "DB password:" "$db_pass"
printf "%-15s %s\n" "WP install:" "$wp_install"
printf "%-15s %s\n" "WP user:" "$wp_user"
printf "%-15s %s\n" "WP password:" "$wp_pass"
printf "%-15s %s\n" "Dev mode:" "$dev_mode"


# START FUNCTIONS

# Creates an SFTP user and sets directory permissions for a virtual host.
vhost_create_user() {

	# create sftp group if not available
	if ! getent group sftp &>/dev/null; then groupadd sftp; fi
	
	# creating site structure
	echo "Updating site structure and permissions..."
	print_colored green "Using ${vpath} with owner ${sftp_user}"
	create_folder "${vpath}"
	create_folder "${vpath}/backups"
	create_folder "${vpath}/logs"
	create_folder "${vpath}/www"

	# create sftp user
	echo "Creating user $sftp_user ..."
	if ! id -u "${sftp_user}" &>/dev/null; then
		useradd -m -d "${vpath}" -s /usr/sbin/nologin -p "$(openssl passwd -1 "${sftp_pass}")" "${sftp_user}"
		usermod -aG sftp "${sftp_user}"
		echo "User: ${sftp_user}" > "${vpath}/logs/user.sftp.log"
		echo "Pass: ${sftp_pass}" >> "${vpath}/logs/user.sftp.log"
		print_colored green "Created ${sftp_user} with pass ${sftp_pass} for ${vpath}"
	else
		print_colored cyan "User ${sftp_user} already exists, updating..."
		usermod -d "${vpath}" -s /usr/sbin/nologin "${sftp_user}"
		echo "${sftp_user}:${sftp_pass}" | chpasswd
		echo "User: ${sftp_user}" >> "${vpath}/logs/user.sftp.log"
		echo "Pass: ${sftp_pass}" >> "${vpath}/logs/user.sftp.log"
		print_colored green "Updated ${sftp_user} with pass ${sftp_pass} for ${vpath}"
	fi
	
	# permissions
	chown -R root:root "${vpath}"
	chown -R "${sftp_user}":"${sftp_user}" "${vpath}/backups"
	chown -R "${sftp_user}":"${sftp_user}" "${vpath}/www"
	chmod -R 0755 "${vpath}"

}


# save the new database credentials
save_db_credentials() {
    # Create the log file and write the database details to it
    echo "Database: ${db_user}" > "${vpath}/logs/user.mysql.log"
    echo "Username: ${db_user}" >> "${vpath}/logs/user.mysql.log"
    echo "Password: ${db_pass}" >> "${vpath}/logs/user.mysql.log"
    echo "Host: ${db_host}" >> "${vpath}/logs/user.mysql.log"
    echo "Port: ${db_port}" >> "${vpath}/logs/user.mysql.log"
}


# Creates a database and unique user for the virtual host
vhost_create_database() {

	echo "Creating database and user..."
	
	# check if database exists
    if mysql -e "USE ${db_user};" &>/dev/null; then
        print_colored cyan "Database ${db_user} already exists."
    else
		mysql -e "CREATE DATABASE IF NOT EXISTS ${db_user};"
		if [ ${?} = 0 ]; then
			print_colored green "Database ${db_user} created."
		else
			print_colored red "Database ${db_user} creation failed."
		fi
	fi
	
	# update or create user
	mysql -e "CREATE USER IF NOT EXISTS '${db_user}'@'${db_host}' IDENTIFIED BY '${db_pass}';"
	mysql -e "ALTER USER '${db_user}'@'${db_host}' IDENTIFIED BY '${db_pass}';"
	mysql -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES, REFERENCES, TRIGGER, LOCK TABLES, SHOW VIEW ON ${db_user}.* TO '${db_user}'@'${db_host}';"
	mysql -e "FLUSH PRIVILEGES;"
	save_db_credentials
	print_colored green "User ${db_user} password and priviledges created/updated."
	
}


# install a fresh wordpress site
install_wp() {    
   
    export WP_CLI_CACHE_DIR=/tmp
	DOCHM="${vpath}/www"
	cd ${DOCHM}
	
	# check for existing wp-config.php file
	if test -e "${DOCHM}/wp-config.php"; then
		
		# update credentials
		print_colored cyan "wp-config.php file exists, updating..."
		wp config set DB_HOST "${db_host}" --type=constant --allow-root
		wp config set DB_NAME "${db_user}" --type=constant --allow-root
		wp config set DB_USER "${db_user}" --type=constant --allow-root
		wp config set DB_PASSWORD "${db_pass}" --type=constant --allow-root
		
		# finish
		print_colored cyan "WordPress credentials are up to date on ${domain}"
		
	else
		
		# download and install
		echo "Downloading wordpress..."
		wp core download --path=${DOCHM} --allow-root --quiet
		
		echo 'Installing WordPress...'
		wp core config --dbname="${db_user}" --dbuser="${db_user}" --dbpass="${db_pass}" --dbhost="${db_host}" --dbprefix="wp_" --path="${DOCHM}" --allow-root --quiet
		wp core install --url="${domain}" --title="WordPress" --admin_user="${wp_user}" --admin_password="${wp_pass}" --admin_email="change-me@${domain}" --skip-email --path="${DOCHM}" --allow-root --quiet
		
		echo 'Finalizing WordPress...'
		wp site empty --yes --uploads --path="${DOCHM}" --allow-root --quiet
		wp plugin delete $(wp plugin list --status=inactive --field=name --path="${DOCHM}" --allow-root --quiet) --path="${DOCHM}" --allow-root --quiet
		wp theme delete $(wp theme list --status=inactive --field=name --path="${DOCHM}" --allow-root --quiet) --path="${DOCHM}" --allow-root --quiet
		wp config shuffle-salts --path="${DOCHM}" --allow-root --quiet
		wp option update permalink_structure '/%postname%/' --path="${DOCHM}" --allow-root --quiet
		
		# finish
		print_colored cyan "WordPress is now installed on ${domain}"
		
	fi
		
	# download htaccess
	if [ ! -f "${DOCHM}/.htaccess" ]; then
		curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/wp/htaccess > /tmp/htaccess.txt
		cat /tmp/htaccess.txt | grep -q "WordPress" && cp /tmp/htaccess.txt ${DOCHM}/.htaccess && print_colored green "Success: .htaccess updated." || print_colored red "Error downloading .htaccess ..."
		rm /tmp/htaccess
	fi
		
	# create control file for letsencrypt
	if [ ! -f "${DOCHM}/ssl-test.txt" ]; then
		echo "OK" > ${DOCHM}/ssl-test.txt
	fi
		
	# permissions
	chown -R "${sftp_user}":"${sftp_user}" "${vpath}/www"
	chmod -R 0755 "${vpath}/www"
			
	# save credentials
	echo "WP User: ${wp_user}" > "${vpath}/logs/user.wp.log"
	echo "WP Pass: ${wp_pass}" >> "${vpath}/logs/user.wp.log"
		    
}


# create ols virtual host and listener
create_ols_vhost() {
	
	# vhconf.conf file for the virtual hosting settings
	VHDIR="/usr/local/lsws/conf/vhosts/${domain}"
	create_folder "${VHDIR}"
	VHCONF="${VHDIR}/vhconf.conf"
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/ols/vhconf.conf > /tmp/vhconf.conf
	cat /tmp/vhconf.conf | grep -q "docRoot" && cp /tmp/vhconf.conf ${VHCONF} && print_colored green "Success: vhconf.conf updated." || print_colored red "Error downloading vhconf.conf ..."
	rm /tmp/vhconf.conf
	
	# fix paths and other info
	sed -i "s~##domain##~${domain}~g" "${VHCONF}"
	sed -i "s~##aliases##~${aliases}~g" "${VHCONF}"
	sed -i "s~##path##~${vpath}~g" "${VHCONF}"
	sed -i "s~##user##~${sftp_user}~g" "${VHCONF}"
	scripthandler="lsphp${php//./}"
	sed -i "s~##php##~${scripthandler}~g" "${VHCONF}"


	# create map rule for the listener block
	if [ -n "$aliases" ]; then
	  aliases_map="$(echo "$aliases" | sed 's/,/, /g')"
	  newmap="map ${domain} ${domain}, ${aliases_map}"
	else
	  newmap="map ${domain}"
	fi

	# append it to httpd_config.conf
	if ! grep -q "$newmap" "/usr/local/lsws/conf/httpd_config.conf"; then
	  sed -i -e '/listener/,/\}/s/\}/  '"$newmap"'\n}/' "/usr/local/lsws/conf/httpd_config.conf"
	fi
	
	# create virtualhost block for httpd_config.conf
	virtualhost="
    virtualhost ${domain} {
        vhRoot                  ${vpath}
        configFile              ${VHCONF}
        allowSymbolLink         2
        enableScript            1
        restrained              1
		setUIDMode              2
        user                    ${sftp_user}
        group                   ${sftp_user}
    }
	"
	
	# append it
	if ! grep -qF "virtualhost ${domain}" "/usr/local/lsws/conf/httpd_config.conf"; then
		echo "$virtualhost" >> "/usr/local/lsws/conf/httpd_config.conf"
	fi
	
	# permissions
	chown -R lsadm:lsadm /usr/local/lsws/conf
	
	# restart
	systemctl restart lsws
		
	# generate php pools
	find /etc/php/*/fpm/pool.d -maxdepth 1 -type f -name "${domain}.conf" -delete
	PHP_POOL_COUNT=$(calculate_memory_configs "PHP_POOL_COUNT")
	PHP_BACKLOG=$(calculate_memory_configs "PHP_BACKLOG")
	curl -skL https://raw.githubusercontent.com/peixotorms/ols/main/configs/php/pool.conf > /tmp/pool.conf
	for version in 7.4 8.0 8.1 8.2; do
		CHECK="/etc/php/${version}/fpm/pool.d"
		POOL_LOC="${CHECK}/${domain}.conf"
		if [ -d "${CHECK}" ]; then
			AVAIL_POOL_PORT=$(find_available_php_port)
			cat /tmp/pool.conf | grep -q "user" && cp /tmp/pool.conf ${POOL_LOC} && print_colored green "Success: pool.conf created for for PHP ${version} FPM." || print_colored red "Error downloading pool.conf ..."
			sed -i "s~#user#~$sftp_user~g" "${POOL_LOC}"
			sed -i "s~#port#~$AVAIL_POOL_PORT~g" "${POOL_LOC}"
			sed -i "s~#children#~$PHP_POOL_COUNT~g" "${POOL_LOC}"
			sed -i "s~#vpath#~${vpath}~g" "${POOL_LOC}"
			sed -i "s~^.*backlog.*$~listen.backlog = ${PHP_BACKLOG}~g" "${POOL_LOC}"
			
			# update vhconf.conf php ports to match with the php pool for each version
			if [ "$version" = "7.4" ]; then
				sed -i "s~127.0.0.1:9000~127.0.0.1:${AVAIL_POOL_PORT}~g" "${VHCONF}"
			elif [ "$version" = "8.0" ]; then
				sed -i "s~127.0.0.1:9001~127.0.0.1:${AVAIL_POOL_PORT}~g" "${VHCONF}"
			elif [ "$version" = "8.1" ]; then
				sed -i "s~127.0.0.1:9002~127.0.0.1:${AVAIL_POOL_PORT}~g" "${VHCONF}"
			elif [ "$version" = "8.2" ]; then
				sed -i "s~127.0.0.1:9003~127.0.0.1:${AVAIL_POOL_PORT}~g" "${VHCONF}"
			fi
			
			# finish
			sleep 5
			systemctl restart php${version}-fpm
			((AVAIL_POOL_PORT++))
		else
			print_colored red "Directory for PHP ${version} does not exist"
		fi
	done
	rm /tmp/pool.conf
		
}


# create a ssl certificate
create_letsencrypt_ssl() {
	
	# merge domain and aliases
	domains="${domain}${aliases:+,${aliases}}"
	email="no-reply@${domain}"
	
	# Convert the comma-separated string to an array
	IFS=',' read -ra domains_array <<< "$domains"

	# Loop through the domains and make a curl request to the domain
	all_successful=true
	failed_domains=()
	for domain in "${domains_array[@]}"; do
		echo "Testing ${domain}..."
		response=$(curl -sSL -H "Cache-Control: no-cache" -k "http://${domain}/ssl-test.txt?nocache=$(date +%s)")
		if [[ "${response}" == "OK" ]]; then
			print_colored yellow "${domain} found"
		else
			print_colored red "Failed to open: http://${domain}/ssl-test.txt?nocache=$(date +%s)"
			all_successful=false
			failed_domains+=("$domain")
		fi
	done

	# Check if all domains were successful
	if $all_successful; then
		print_colored green "All domains were successful, creating ssl..."
		certbot certonly --expand --agree-tos --non-interactive --keep-until-expiring --rsa-key-size 2048 -m "${email}" --webroot -w "${DOCHM}" -d "${domains}"
		systemctl restart lsws
	else
		print_colored red "Failed domains: ${failed_domains[@]}"
	fi

}


# END FUNCTIONS


# run
vhost_create_user
vhost_create_database
install_wp
create_ols_vhost
create_letsencrypt_ssl

# finish
print_colored green "All done!"
