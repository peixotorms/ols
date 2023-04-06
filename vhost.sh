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


TEMP=$(getopt -o '' --long domain:,aliases:,ssl:,php:,path:,sftp_user:,sftp_pass:,db_host:,db_port:,db_user:,db_pass:,wp_install:,wp_user:,wp_pass:,dev_mode: -n "$(basename -- "$0")" -- "$@")
eval set -- "$TEMP"

# Parse command-line arguments
while true; do
    case "$1" in
        --domain)
            domain="${2}"; shift 2
            if ! validate_domain "$domain"; then
                print_colored red "Invalid domain name $domain"; exit 1
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
			
			# Initialize default values
			ssl="yes"
			php="8.0"
			db_host="localhost"
			db_port="3306"
			wp_install="yes"
			dev_mode="yes"
			aliases=()
			
            ;;
        --aliases)
            IFS=',' read -ra aliases <<< "${2:-}"; shift 2
            for alias in "${aliases[@]}"; do
                if ! validate_domain "$alias"; then
                    print_colored red "Invalid alias domain: $alias"; exit 1
                fi
            done
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
        --path)
            path="${2:-/home/sites/$domain_no_www}"; shift 2
            if [[ "${path%/}" != *"/$domain_no_www" ]]; then
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
		--help)
			echo ""
			printf "Usage: bash $(basename -- "$0") --domain <domain_name> [OPTIONS]\n"
			echo ""
			printf "Options:\n"
			printf "%-4s%-11s%-49s\n" "" "--domain (required)" "Domain name to set up"
			printf "%-4s%-11s%-49s\n" "" "--aliases (optional)" "Comma-separated list of domain aliases"
			printf "%-4s%-11s%-49s\n" "" "--ssl (optional)" "Enable or disable SSL. Default is 'yes'"
			printf "%-4s%-11s%-49s\n" "" "--php (optional)" "PHP version to install. Must be 7.4, 8.0, 8.1, or 8.2. Default is '8.0'"
			printf "%-4s%-11s%-49s\n" "" "--path (optional)" "Path to install website. Default is '/home/sites/<domain_name>'"
			printf "%-4s%-11s%-49s\n" "" "--sftp_user (optional)" "SFTP username. Default is generated from domain name"
			printf "%-4s%-11s%-49s\n" "" "--sftp_pass (optional)" "SFTP password. Default is random"
			printf "%-4s%-11s%-49s\n" "" "--db_host (optional)" "Database host. Default is 'localhost'"
			printf "%-4s%-11s%-49s\n" "" "--db_port (optional)" "Database port. Default is '3306'"
			printf "%-4s%-11s%-49s\n" "" "--db_user (optional)" "Database username. Default is generated from domain name"
			printf "%-4s%-11s%-49s\n" "" "--db_pass (optional)" "Database password. Default is random"
			printf "%-4s%-11s%-49s\n" "" "--wp_install (optional)" "Install WordPress or not. Default is 'yes'"
			printf "%-4s%-11s%-49s\n" "" "--wp_user (optional)" "WordPress username. Default is generated from domain name"
			printf "%-4s%-11s%-49s\n" "" "--wp_pass (optional)" "WordPress password. Default is random"
			printf "%-4s%-11s%-49s\n" "" "--dev_mode (optional)" "Enable or disable developer mode. Default is 'yes'"
			printf "%-4s%-11s%-49s\n" "" "-h, --help" "Show this help message"
			echo ""
			printf "Examples:\n"
			printf "%-4s%-11s%-49s\n" "" "bash $(basename -- "$0") --domain example.com --ssl no --php 7.4"
			printf "%-4s%-11s%-49s\n" "" "bash $(basename -- "$0") --domain example.com --aliases example.net,example.org"
			echo ""
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


# Add your script logic below to process the options


printf "%-15s %s\n" "Domain:" "$domain"
printf "%-15s %s\n" "Aliases:" "${alias_list[*]}"
printf "%-15s %s\n" "SSL:" "$ssl"
printf "%-15s %s\n" "PHP version:" "$php"
printf "%-15s %s\n" "Path:" "$path"
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

