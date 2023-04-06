#!/bin/bash

################################################
# Common functions, to be included on others
################################################


# This function executes the given command and suppresses its output if the VERBOSE variable is not set to '1'. 
# Usage: silent <command>
silent { if [ "${VERBOSE}" = '1' ]; then "$@"; else "$@" >/dev/null 2>&1; fi; }


# This function creates a 32-character password with three special characters in a random position
gen_rand_pass() {
    random_string=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    for i in {1..3}; do
        pos=$((RANDOM % 24 + 5))
        special_char=('-' '_' ',')
        random_string="${random_string:0:$(($pos-1))}${special_char[RANDOM % 3]}${random_string:$pos}"
    done
    echo "$random_string"
}


# This function can be used to print text in a specified color using ANSI escape codes. 
# It takes a color as its first argument (red, green, yellow, blue, magenta, cyan, or default), followed by the text that you want to print
print_colored() {
    local color=$1
    shift
    case "$color" in
        red) color_code=31;;
        green) color_code=32;;
        yellow) color_code=33;;
        blue) color_code=34;;
        magenta) color_code=35;;
        cyan) color_code=36;;
        *) color_code=0;;
    esac
    printf "\033[${color_code}m%s\033[0m\n" "$@"
}


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
update_system
{
	if [ -d /etc/needrestart/conf.d ]; then
		echo 'Disabling pending kernel upgrade notice...'
		echo -e "\$nrconf{restart} = 'l';\n\$nrconf{kernelhints} = 0;" > /etc/needrestart/conf.d/disable.conf
	fi
	
	DEBIAN_FRONTEND=noninteractive silent apt update
	DEBIAN_FRONTEND=noninteractive silent apt upgrade -y
	DEBIAN_FRONTEND=noninteractive silent apt autoremove -y
}


# This function validates if a given domain name is valid
validate_domain() { 
	local domain_regex="^([A-Za-z0-9]+(-[A-Za-z0-9]+)*\.)+[A-Za-z]{2,}$"; [[ $1 =~ $domain_regex || $1 == "localhost" ]]; 
}


# This function validates if a given PHP version is allowed
validate_php_version() {
    local allowed_versions=("7.4" "8.0" "8.1" "8.2")
    for version in "${allowed_versions[@]}"; do
        [[ $1 == $version ]] && return 0
    done
    return 1
}

# This function generates a valid user name based on the given parameter
generate_user_name() {
    local user_name=$(echo "$1" | tr -dc '[:alnum:]' | tr '[:upper:]' '[:lower:]')
    if [[ ${#user_name} -lt 3 || ${user_name:0:1} =~ [0-9] ]]; then
        user_name="user_${user_name}"
    fi
    echo "${user_name:0:32}"
}

# Create folder if it doesn't exist
create_folder { [[ ! -d "$1" ]] && mkdir -p "$1"; }

# This function creates a file if it doesn't exist
create_file() { [ ! -f "${1}" ] && touch "${1}"; }
