#!/bin/bash

##############################################################################
#		OpenLiteSpeed, LetsEncrypt                                           #
#       PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI                       #
#       Percona Server 8.0 for MySQL, Postfix and Redis                      #
#		Author: Raul Peixoto, WP Raiser										 #
##############################################################################

# import common functions
source <(curl -sSf https://raw.githubusercontent.com/peixotorms/ols/main/inc/common.sh)

#!/bin/bash

validate_domain() { 
	local domain_regex="^([A-Za-z0-9]+(-[A-Za-z0-9]+)*\.)+[A-Za-z]{2,}$"; [[ $1 =~ $domain_regex || $1 == "localhost" ]]; 
}


validate_php_version() {
    local allowed_versions=("7.4" "8.0" "8.1" "8.2")
    for version in "${allowed_versions[@]}"; do
        [[ $1 == $version ]] && return 0
    done
    return 1
}

generate_user_name() {
    local user_name=$(echo "$1" | tr -dc '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    if [[ ${#user_name} -lt 3 || ${user_name:0:1} =~ [0-9] ]]; then
        user_name="user_${user_name}"
    fi
    echo "${user_name:0:32}"
}


# Initialize default values
ssl="yes"
php="8.0"
db_host="localhost"
db_port="3306"
wp_install="yes"
dev_mode="yes"
aliases=()

TEMP=$(getopt -o '' --long domain:,aliases:,ssl:,php:,path:,sftp_user:,sftp_pass:,db_host:,db_port:,db_user:,db_pass:,wp_install:,wp_user:,wp_pass:,dev_mode: -n "$(basename -- "$0")" -- "$@")
eval set -- "$TEMP"

# start options
while true; do
    case "$1" in
        --domain)
            domain="${2}"; shift 2
            if ! validate_domain "$domain"; then
                echo "Invalid domain name"; exit 1
            fi
			
			# Create new variable without www subdomain
            domain_no_www="${domain/www.}"

            # Set default values based on domain
            path="/home/sites/$domain_no_www"
            sftp_user="$(generate_user_name "$domain_no_www")"
            db_user="$(generate_user_name "$domain_no_www")"
            wp_user="$(generate_user_name "$domain_no_www")"
			
            # Set default passwords
            sftp_pass="$(gen_rand_pass)"
            db_pass="$(gen_rand_pass)"
            wp_pass="$(gen_rand_pass)"
			
            ;;
        --aliases)
            IFS=',' read -ra aliases <<< "${2:-}"; shift 2
            for alias in "${aliases[@]}"; do
                if ! validate_domain "$alias"; then
                    echo "Invalid alias domain: $alias"; exit 1
                fi
            done
            ;;
        --ssl)
            case "${2,,}" in
                yes|no)
                    ssl="${2,,}"; shift 2
                    ;;
                *)
                    echo "Invalid SSL value: $2. Must be 'yes' or 'no'."; exit 1
                    ;;
            esac
            ;;
        --php)
            case "${2,,}" in
                7.4|8.0|8.1|8.2)
                    php="${2,,}"; shift 2
                    ;;
                *)
                    echo "Invalid PHP version: $2. Must be 7.4, 8.0, 8.1, or 8.2."; exit 1
                    ;;
            esac
            ;;
        --path)
            path="${2:-/home/sites/$domain_no_www}"; shift 2
            if [[ "${path%/}" != *"/$domain_no_www" ]]; then
                echo "Invalid path: must include domain as the last directory name"; exit 1
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
				echo "Invalid SFTP password format. Only alphanumeric characters and these special characters are allowed: ,+=@-_!"; exit 1
			elif [[ "${#sftp_pass}" -lt 8 ]] || [[ "${#sftp_pass}" -gt 32 ]]; then
				echo "Invalid SFTP password length. Must be between 8 and 32 characters."; exit 1
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
                echo "Invalid database password format. Only alphanumeric characters and these special characters are allowed: ,+=@-_!"; exit 1
            elif [[ "${#db_pass}" -lt 8 ]] || [[ "${#db_pass}" -gt 32 ]]; then
                echo "Invalid database password length. Must be between 8 and 32 characters."; exit 1
            fi
            shift 2
            ;;
        --wp_install)
            case "${2,,}" in
                yes|no)
                    wp_install="${2,,}"; shift 2
                    ;;
                *)
                    echo "Invalid WordPress installation value: $2. Must be 'yes' or 'no'."; exit 1
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
                echo "Invalid WordPress password format. Only alphanumeric characters and these special characters are allowed: ,+=@-_!"; exit 1
            elif [[ "${#wp_pass}" -lt 8 ]] || [[ "${#wp_pass}" -gt 32 ]]; then
                echo "Invalid WordPress password length. Must be between 8 and 32 characters."; exit 1
            fi
            shift 2
            ;;
        --dev_mode)
            case "${2,,}" in
                yes|no)
                    dev_mode="${2,,}"; shift 2
                    ;;
                *)
                    echo "Invalid dev mode value: $2. Must be 'yes' or 'no'."; exit 1
            fi
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Internal error!"; exit 1
            ;;
    esac
	
	if [[ "$#" == "0" ]]; then
        break
    fi
	
done

# Ensure --domain is mandatory
if [[ -z "$domain" ]]; then
    echo "Error: --domain option is required."; exit 1
fi


# Add your script logic below to process the options


echo "Domain: $domain"
echo "Aliases: ${alias_list[*]}"
echo "SSL: $ssl"
echo "PHP version: $php"
echo "Path: $path"
echo "SFTP user: $sftp_user"
echo "SFTP password: $sftp_pass"
echo "DB host: $db_host"
echo "DB port: $db_port"
echo "DB user: $db_user"
echo "DB password: $db_pass"
echo "WP install: $wp_install"
echo "WP user: $wp_user"
echo "WP password: $wp_pass"
echo "Dev mode: $dev_mode"
