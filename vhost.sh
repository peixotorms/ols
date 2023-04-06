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
    local domain_regex="^((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)+[A-Za-z]{2,6}$"
    [[ $1 =~ $domain_regex ]]
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


TEMP=$(getopt -o '' --long domain:,aliases:,ssl:,php:,path:,sftp_user:,sftp_pass:,db_host:,db_port:,db_user:,db_pass:,wp_install:,wp_user:,wp_pass:,dev_mode: -n "$(basename -- "$0")" -- "$@")
eval set -- "$TEMP"

while true; do
    case "$1" in
        --domain)
            domain="$2"; shift 2
            if ! validate_domain "$domain"; then
                echo "Invalid domain name"; exit 1
            fi
            ;;
        --aliases)
            IFS=',' read -ra alias_list <<< "$2"; shift 2
            for alias in "${alias_list[@]}"; do
                if ! validate_domain "$alias"; then
                    echo "Invalid alias domain: $alias"; exit 1
                fi
            done
            ;;
        --ssl)
            ssl="$2"; shift 2
            if [[ "$ssl" != "yes" && "$ssl" != "no" ]]; then
                echo "Invalid SSL option"; exit 1
            fi
            ;;
        --php)
            php="$2"; shift 2
            if ! validate_php_version "$php"; then
                echo "Invalid PHP version"; exit 1
            fi
            ;;
        --path)
            path="$2"; shift 2
            if [[ -z "$path" ]]; then
                path="/home/sites/$domain"
            elif [[ "${path%/}" != *"/$domain" ]]; then
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
            sftp_pass="$2"; shift 2
            if [[ -z "$sftp_pass" ]]; then
                sftp_pass=$(gen_rand_pass)
            elif ! [[ $sftp_pass =~ ^[-;,+=@[:alnum:]]{8,32}$ ]]; then
                echo "Invalid SFTP password"; exit 1
            fi
            ;;
        --db_host)
            db_host="$2"; shift 2
            db_host="${db_host:-localhost}"
            ;;
        --db_port)
            db_port="$2"; shift 2
            db_port="${db_port:-3306}"
            ;;
                --db_user)
            db_user="$2"; shift 2
            if [[ -z "$db_user" ]]; then
                db_user=$(generate_user_name "$domain")
            fi
            ;;
        --db_pass)
            db_pass="$2"; shift 2
            if [[ -z "$db_pass" ]]; then
                db_pass=$(gen_rand_pass)
            elif ! [[ $db_pass =~ ^[-;,+=@[:alnum:]]{8,32}$ ]]; then
                echo "Invalid DB password"; exit 1
            fi
            ;;
        --wp_install)
            wp_install="$2"; shift 2
            if [[ "$wp_install" != "yes" && "$wp_install" != "no" ]]; then
                echo "Invalid WP install option"; exit 1
            fi
            ;;
        --wp_user)
            wp_user="$2"; shift 2
            if [[ -z "$wp_user" ]]; then
                wp_user=$(generate_user_name "$domain")
            fi
            ;;
        --wp_pass)
            wp_pass="$2"; shift 2
            if [[ -z "$wp_pass" ]]; then
                wp_pass=$(gen_rand_pass)
            elif ! [[ $wp_pass =~ ^[-;,+=@[:alnum:]]{8,32}$ ]]; then
                echo "Invalid WP password"; exit 1
            fi
            ;;
        --dev_mode)
            dev_mode="$2"; shift 2
            if [[ "$dev_mode" != "yes" && "$dev_mode" != "no" ]]; then
                echo "Invalid dev_mode option"; exit 1
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
done

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
