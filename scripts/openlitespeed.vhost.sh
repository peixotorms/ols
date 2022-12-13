#!/bin/bash
# /********************************************************************
# LiteSpeed domain setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2022
# @Version: 2.1
# *********************************************************************/
MY_DOMAIN=''
MY_DOMAIN2=''
WWW_PATH='/home/sites'
LSDIR='/usr/local/lsws'
WEBCF="${LSDIR}/conf/httpd_config.conf"
VHDIR="${LSDIR}/conf/vhosts"
EMAIL='localhost'
BOTCRON='/etc/cron.d/certbot'
CKREG="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*\
@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
PHPVER=lsphp80
LSPHPVERLIST=(71 72 73 74 80 81)
USER='www-data'
GROUP='www-data'
DOMAIN_PASS='ON'
DOMAIN_SKIP='OFF'
EMAIL_SKIP='OFF'
TMP_YN='OFF'
ISSUECERT='OFF'
WORDPRESS='OFF'
DB_TEST=0
EPACE='        '

echoR() {
    echo -e "\e[31m${1}\e[39m"
}
echoG() {
    echo -e "\e[32m${1}\e[39m"
}
echoY() {
    echo -e "\e[33m${1}\e[39m"
}
echoB() {
    echo -e "\033[1;4;94m${1}\033[0m"
}
echow(){
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}

show_help() {
    case ${1} in
    "1")
        echo -e "\033[1mOPTIONS\033[0m"
        echow "-D, --domain [DOMAIN_NAME]"
        echo "${EPACE}${EPACE}If you wish to add www domain , please attach domain with www"
        echow "-LE, --letsencrypt [EMAIL]"
        echo "${EPACE}${EPACE}Issue let's ecnrypt certificate, must follow with E-mail address."
        echow "-W, --wordpress"
        echo "${EPACE}${EPACE}This will install Wordpress."
        echo "${EPACE}${EPACE}Example: ./vhsetup.sh -d www.example.com -le admin@example.com -w"
        echo "${EPACE}${EPACE}Above example will create a virtual host with www.example.com and example.com domain"
        echo "${EPACE}${EPACE}Issue and install Let's encrypt certificate."
        echow "--delete [DOMAIN_NAME]"
        echo "${EPACE}${EPACE}This will remove the domain from listener and virtual host config, the document root will remain."
        echow '-H, --help'
        echo "${EPACE}${EPACE}Display help and exit."
        exit 0
    ;;    
    "2")
        echoY "If you need to install cert manually later, please run this script again." 
        echo ''
    ;;  
    "3")
        echo "Please make sure you have $LSDIR/password.mysql file with your root mysql password."
    ;;  
    esac
}
check_os() {
    if [ -f /etc/redhat-release ]; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
    elif [ -f /etc/lsb-release ]; then
        OSNAME=ubuntu
    elif [ -f /etc/debian_version ]; then
        OSNAME=debian
    fi
}
check_provider()
{
    if [[ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" =~ (EC2|ec2) ]]; then 
        PROVIDER='aws'
    elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
        PROVIDER='google'
    elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
        PROVIDER='aliyun'  
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        PROVIDER='azure'    
    elif [ -e /etc/oracle-cloud-agent/ ]; then
        PROVIDER='oracle'             
    else
        PROVIDER='undefined'  
    fi
}
check_home_path()
{
    if [ ${PROVIDER} = 'aws' ] && [ -d /home/ubuntu ]; then 
        HM_PATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'google' ] && [ -d /home/ubuntu ]; then 
        HM_PATH='/home/ubuntu'  
    elif [ ${PROVIDER} = 'aliyun' ] && [ -d /home/ubuntu ]; then
        HM_PATH='/home/ubuntu'
    elif [ ${PROVIDER} = 'oracle' ] && [ -d /home/ubuntu ]; then
        HM_PATH='/home/ubuntu'        
    else
        HM_PATH='/root'
    fi    
}
check_root(){
    if [ $(id -u) -ne 0 ]; then
        echoR "Please run this script as root user or use sudo"
        exit 2
    fi
}
check_process(){
    ps aux | grep ${1} | grep -v grep >/dev/null 2>&1
}
check_php_version(){
    PHP_MA="$(php -r 'echo PHP_MAJOR_VERSION;')"
    PHP_MI="$(php -r 'echo PHP_MINOR_VERSION;')"
    if [ -e ${LSDIR}/lsphp${PHP_MA}${PHP_MI}/bin/php ]; then
        PHPVER="lsphp${PHP_MA}${PHP_MI}"
    fi
}

check_webserver(){
    if [ -e ${LSDIR}/bin/openlitespeed ]; then
        if [ -e "${WEBCF}" ]; then
            VH_CONF_FILE="${VHDIR}/${MY_DOMAIN}/vhconf.conf"
        else
            echoR "${WEBCF} does not exist, exit!"
            exit 1  
        fi
    else 
        echoR 'No web server detect, exit!'
        exit 2
    fi    
}

fst_match_line(){
    FIRST_LINE_NUM=$(grep -n -m 1 "${1}" "${2}" | awk -F ':' '{print $1}')
}
fst_match_before(){
    FIRST_NUM_BEFORE=$(grep -B 5 ${1} ${2} | grep -n -m 1 ${3} | awk -F ':' '{print $1}')
}
fst_match_before_line(){
    fst_match_before ${1} ${2} ${3}
    FIRST_BEFORE_LINE_NUM=$((${FIRST_LINE_NUM}+${FIRST_NUM_BEFORE}-1))
}
fst_match_after(){
    FIRST_NUM_AFTER=$(tail -n +${1} ${2} | grep -n -m 1 ${3} | awk -F ':' '{print $1}')
}
lst_match_line(){
    fst_match_after ${1} ${2} ${3}
    LAST_LINE_NUM=$((${FIRST_LINE_NUM}+${FIRST_NUM_AFTER}-1))
}

install_ed() {
    if [ -f /bin/ed ]; then
        echoG "ed exist"
    else
        echoG "no ed, ready to install"
        if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
            apt-get install ed -y >/dev/null 2>&1
        elif [ "${OSNAME}" = 'centos' ]; then
            yum install ed -y >/dev/null 2>&1
        fi
    fi
}
create_file(){
    if [ ! -f ${1} ]; then
        touch ${1}
    fi
}
create_folder(){
    if [ ! -d "${1}" ]; then
        mkdir ${1}
    fi
}
change_owner() {
    chown -R ${USER}:${GROUP} ${DOCHM}
}
line_insert(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    ADDNUM=${4:-0} 
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        LINENUM=$((${LINENUM}+${4}))
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}
install_wp_cli() {
    if [ ! -e /usr/local/bin/wp ]; then
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi    
    if [ ! -f /usr/bin/php ]; then
        if [ -e ${LSDIR}/${PHPVER}/bin/php ]; then
            ln -s ${LSDIR}/${PHPVER}/bin/php /usr/bin/php
        else
            echoR "${LSDIR}/${PHPVER}/bin/php not exist, please check your PHP version!"
            exit 1 
        fi        
    fi      
}
gen_password(){
    ROOT_PASS=$(cat $LSDIR/password.mysql | head -n 1)
	if [ "${PWSQL}" = '' ]; then
        PWSQL=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi
	if [ "${PWWPADMIN}" = '' ]; then
        PWWPADMIN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi
}

create_db_user(){
    if [ -e $LSDIR/password.mysql ]; then
        gen_password
        mysql -uroot -p${ROOT_PASS} -e "CREATE DATABASE IF NOT EXISTS ${USER};"
        if [ ${?} = 0 ]; then
			echo "Creating database and user access..."
            mysql -uroot -p${ROOT_PASS} -e "CREATE USER IF NOT EXISTS '${USER}'@'localhost' IDENTIFIED BY '${PWSQL}';"
            mysql -uroot -p${ROOT_PASS} -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES, REFERENCES, TRIGGER, LOCK TABLES, SHOW VIEW ON ${USER}.* TO '${USER}'@'localhost';"
			mysql -uroot -p${ROOT_PASS} -e "ALTER USER '${USER}'@'localhost' IDENTIFIED BY '${PWSQL}';"
            mysql -uroot -p${ROOT_PASS} -e "FLUSH PRIVILEGES;"
			echo -en "User: ${USER} \nPass: ${PWSQL}" > "${WWW_PATH}/${DOM1}/logs/user.mysql.log"
			
        else
            echoR "something went wrong when create new database, please proceed to manual installation."
            DB_TEST=1
        fi
    else
        echoR "No DataBase Password, skip!"  
        DB_TEST=1
        show_help 3
    fi    
}

delete_db_user(){
    if [ -e $LSDIR/password.mysql ]; then
        gen_password
		
		if [ -z "$ROOT_PASS" ]
		then
			echoR "No DataBase Password, skip!"  
		else
			if [ -z "$USER" ]
			then
				echoR "No DataBase User, skip!"  
			else
				# delete database and user
				mysql -uroot -p${ROOT_PASS} -e "DROP DATABASE IF EXISTS ${USER};"
				mysql -uroot -p${ROOT_PASS} -e "DELETE FROM mysql.user WHERE User = '${USER}'@'localhost';"
				echoB "Database ${USER} and user ${USER}'@'localhost' deleted!"  
			fi
		fi
		
    else
        echoR "No DataBase Password, skip!"  
        DB_TEST=1
        show_help 3
    fi    
}

install_wp() {
    create_db_user
    if [ ${DB_TEST} = 0 ]; then
        rm -f ${DOCHM}/index.php
        export WP_CLI_CACHE_DIR=/tmp/
		cd ${DOCHM}
		echoG 'Downloading WordPress...'
        wp core download --path=${DOCHM} --allow-root --quiet
		echoG 'Configuring wp-config.php...'
        wp core config --dbname="${USER}" --dbuser="${USER}" --dbpass="${PWSQL}" --dbhost="localhost" --dbprefix="wp_" --path="${DOCHM}" --allow-root --quiet
		echoG 'Installing WordPress...'
		wp core install --url="${MY_DOMAIN}" --title="WordPress" --admin_user="${USER}" --admin_password="${PWWPADMIN}" --admin_email="changeme@${MY_DOMAIN}" --skip-email --path="${DOCHM}" --allow-root --quiet
		echoG 'Finalizing WordPress...'
		wp site empty --yes --uploads --path="${DOCHM}" --allow-root --quiet
		wp plugin delete $(wp plugin list --status=inactive --field=name --path="${DOCHM}" --allow-root --quiet) --path="${DOCHM}" --allow-root --quiet
		wp theme delete $(wp theme list --status=inactive --field=name --path="${DOCHM}" --allow-root --quiet) --path="${DOCHM}" --allow-root --quiet
		wp config shuffle-salts --path="${DOCHM}" --allow-root --quiet
		wp option update permalink_structure '/%postname%/' --path="${DOCHM}" --allow-root --quiet
		
		# save
		echo -en "User: ${USER} \nPass: ${PWWPADMIN}" > "${WWW_PATH}/${DOM1}/logs/user.wp.log"
		
		echoG 'Setting .htaccess'
		set_wp_htaccess
		echoG 'Finish WordPress'
		
        change_owner
        echoG "WP is now installed."    
    fi
}

update_wp() {
    create_db_user
    if [ ${DB_TEST} = 0 ]; then
        export WP_CLI_CACHE_DIR=/tmp/
		cd ${DOCHM}
		echoG 'Configuring wp-config.php...'        
		wp config set DB_HOST 'localhost' --type=constant --allow-root
		wp config set DB_NAME ${USER} --type=constant --allow-root
		wp config set DB_USER ${USER} --type=constant --allow-root
		wp config set DB_PASSWORD ${PWSQL} --type=constant --allow-root	
		
		# permissions
		change_owner
		
		# save
		echo -en "DB User: ${USER} \nDB Pass: ${PWSQL}" > "${WWW_PATH}/${DOM1}/logs/user.wp.log"
        echoG "WP is now reconfigured."    
    fi
}

set_wp_htaccess(){
    create_file "${DOCHM}/.htaccess"
    cat <<EOM >${DOCHM}/.htaccess
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOM
}

check_install_wp() { 
    if [ ${WORDPRESS} = 'ON' ]; then
        check_process 'mysqld\|mariadb'
        if [ ${?} = 0 ]; then
            if [ ! -f ${DOCHM}/wp-config.php ]; then
                install_wp
            else
				echoR 'WordPress existed, updating credentials!'
				update_wp                
            fi    
        else
            echoR 'No MySQL environment, skip!'
        fi                
    fi
}

check_duplicate() {
    grep -w "${1}" ${2} >/dev/null 2>&1
}

restart_lsws(){
    ${LSDIR}/bin/lswsctrl stop >/dev/null 2>&1
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws >/dev/null 2>&1   
}

set_ols_vh_conf() {
    create_folder "${DOCHM}"
    create_folder "${VHDIR}/${DOM1}"
    if [ ! -f "${DOCHM}/index.php" ]; then
        cat <<'EOF' >${DOCHM}/index.php
<?php
phpinfo();
EOF
        change_owner
    fi
	
	# vhost file
	cat > ${VH_CONF_FILE} << EOF
docRoot                   \$VH_ROOT/www
vhDomain                  $MY_DOMAIN
vhAliases                 $MY_DOMAIN2
enableGzip                1
enableBr                  1
enableIpGeo               0
cgroups                   1

errorlog \$VH_ROOT/logs/\$VH_NAME.error.log {
  useServer               0
  logLevel                NOTICE
  rollingSize             256M
  keepDays                21
  compressArchive         1
}

accesslog \$VH_ROOT/logs/\$VH_NAME.access.log {
  useServer               0
  logFormat               "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"
  logHeaders              3
  rollingSize             256M
  keepDays                21
  compressArchive         1
}

index  {
  useServer               0
  indexFiles              index.html, index.php
  autoIndex               0
}

expires  {
  enableExpires           1
}

scripthandler  {
add                     lsapi:${PHPVER} php
}

extprocessor ${PHPVER} {
type                    lsapi
address                 uds://tmp/lshttpd/${MY_DOMAIN}.sock
maxConns                64
env                     PHP_LSAPI_CHILDREN=64
env                     PHP_LSAPI_MAX_REQUESTS=500
env                     LSAPI_AVOID_FORK=1
initTimeout             60
retryTimeout            0
persistConn             1
respBuffer              0
autoStart               1
path                    ${LSDIR}/${PHPVER}/bin/lsphp
backlog                 100
instances               4
extUser                 ${USER}
extGroup                ${GROUP}
runOnStartUp            1
priority                0
memSoftLimit            2047M
memHardLimit            2047M
procSoftLimit           400
procHardLimit           500
}

rewrite  {
enable                  1
autoLoadHtaccess        1
logLevel                0
rules                   <<<END_rules
RewriteCond %{SERVER_PORT} ^80$
RewriteCond %{REQUEST_URI} !^/\.well\-known/acme\-challenge/
RewriteRule .* https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
END_rules

}

vhssl  {
keyFile                 /etc/letsencrypt/live/\$VH_NAME/privkey.pem
certFile                /etc/letsencrypt/live/\$VH_NAME/fullchain.pem
certChain               1
enableECDHE             0
enableDHE               0
renegProtection         1
sslSessionCache         1
sslSessionTickets       1
enableSpdy              15
enableQuic              1
}

EOF
    
	chown -R lsadm:lsadm ${VHDIR}/*
}

set_ols_server_conf() {
	if [ -z "$MY_DOMAIN2" ]; then
        NEWKEY="map                     ${MY_DOMAIN} ${MY_DOMAIN}"    
    else
        NEWKEY="map                     ${MY_DOMAIN} ${MY_DOMAIN}, ${MY_DOMAIN2}"
    fi
	
    PORT_ARR=$(grep "address.*:[0-9]"  ${WEBCF} | awk '{print substr($2,3)}')
    if [  ${#PORT_ARR[@]} != 0 ]; then
        for PORT in ${PORT_ARR[@]}; do 
            line_insert ":${PORT}$"  ${WEBCF} "${NEWKEY}" 2
        done
    else
        echoR 'No listener port detected, listener setup skip!'    
    fi
    echo "
virtualhost ${MY_DOMAIN} {
vhRoot                  ${WWW_PATH}/${DOM1}
configFile              ${VH_CONF_FILE}
allowSymbolLink         1
enableScript            1
restrained              1
user                    ${USER}
group                   ${USER}
}" >>${WEBCF}
}

update_ssl_vh_conf(){
    sed -i 's|localhost|'${EMAIL}'|g' ${VH_CONF_FILE}
    sed -i 's|'${LSDIR}'/conf/example.key|/etc/letsencrypt/live/'${DOM1}'/privkey.pem|g' ${VH_CONF_FILE}
    sed -i 's|'${LSDIR}'/conf/example.crt|/etc/letsencrypt/live/'${DOM1}'/fullchain.pem|g' ${VH_CONF_FILE}
    echoG "\ncertificate has been successfully installed..."  
}

main_set_vh(){
	
	# Directory without www
	CHECK_WWW=$(echo "${1}" | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]]; then
        DOM1=$(echo "${1}" | cut -c 5-)
    else
        DOM1="${1}"
    fi

    create_folder ${WWW_PATH}
    DOCHM="${WWW_PATH}/${DOM1}/www"
	
	# creating site structure
	echo "Updating site structure and permissions..."
	if [[ ! -e "/${WWW_PATH}/${DOM1}/backups" ]]; then mkdir -p "${WWW_PATH}/${DOM1}/backups"; fi
	if [[ ! -e "${WWW_PATH}/${DOM1}/logs" ]]; then mkdir -p "${WWW_PATH}/${DOM1}/logs"; fi
	if [[ ! -e "${WWW_PATH}/${DOM1}/www" ]]; then mkdir -p "${WWW_PATH}/${DOM1}/www"; fi
	
	# create sftp user
	echo "Creating user..."
	[ $(getent group sftp) ] || groupadd sftp
	id -u ${USER} &>/dev/null || useradd ${USER} -d /home/sites/${DOM1} -s /usr/sbin/nologin
	usermod -a -G sftp ${USER}
	if [ "${PWSFTP}" = '' ]; then
        PWSFTP=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi
	yes ${PWSFTP} | passwd ${USER}
	echo -en "User: ${USER} \nPass: ${PWSFTP}" > "${WWW_PATH}/${DOM1}/logs/user.sftp.log"
	echoG "Created ${USER} with pass: ${PWSFTP}"
	
	# ownership & permissions
	chown root:root /home/sites/${DOM1}
	chown ${VUSER}:${VUSER} ${WWW_PATH}/${DOM1}/backups
	chown ${VUSER}:${VUSER} ${WWW_PATH}/${DOM1}/logs
	chown ${VUSER}:${VUSER} ${WWW_PATH}/${DOM1}/www
	chmod -R 0755 ${WWW_PATH}/${DOM1}/www
	chown -R ${USER}:${USER} ${WWW_PATH}/${DOM1}/www

	# continue
	set_ols_vh_conf
    set_ols_server_conf
	restart_lsws
	echoG "Vhost created success!"
    
}

rm_ols_vh_conf(){
	
	if [ "${MY_DOMAIN}" != '' ]; then
        if [ -d "${VHDIR}/${MY_DOMAIN}" ]; then
			echoG "Remove virtual host config: ${VHDIR}/${MY_DOMAIN}"
			rm -rf "${VHDIR}/${MY_DOMAIN}"
		fi
    fi
    if [ "${MY_DOMAIN2}" != '' ]; then
        if [ -d "${VHDIR}/${MY_DOMAIN2}" ]; then
			echoG "Remove virtual host config: ${VHDIR}/${MY_DOMAIN2}"
			rm -rf "${VHDIR}/${MY_DOMAIN2}"
		fi
    fi
	
	# finish
	echoB "Finished removing virtual host configs."
}

rm_dm_ols_svr_conf(){
	if [ "${1}" != '' ]; then
		# remove map, virtual host, line breaks
		sed -i "/map.*${1}/d" ${WEBCF}
		sed -i "/virtualhost ${1} {/,/}/d" ${WEBCF}
		sed -i 'N;/^\n$/d;P;D' ${WEBCF}
		echoG "Removing ${1} domain from listeners..."
    else
        echoR "virtualhost ${1} empty, please remove it manually!"
    fi
	
}

rm_le_cert(){
    echoG 'Remote Lets Encrypt Certificate'
	if [ "${MY_DOMAIN}" != '' ]; then
        certbot delete --cert-name ${MY_DOMAIN} >/dev/null 2>&1
    fi
    if [ "${MY_DOMAIN2}" != '' ]; then
        certbot delete --cert-name ${MY_DOMAIN2} >/dev/null 2>&1
    fi
}

rm_main_conf(){

	if [ "${MY_DOMAIN}" != '' ]; then
        grep -w "map.*${MY_DOMAIN}" ${WEBCF} >/dev/null 2>&1
		if [ ${?} = 0 ]; then
			echoG "Domain ${MY_DOMAIN} exists, deleting..."        
			rm_ols_vh_conf
			rm_dm_ols_svr_conf ${MY_DOMAIN}
			restart_lsws
			echoB "Domain remove finished!"
		else 
			echoR "Domain does not found, exit!"  
		fi
    fi
    if [ "${MY_DOMAIN2}" != '' ]; then
        grep -w "map.*${MY_DOMAIN2}" ${WEBCF} >/dev/null 2>&1
		if [ ${?} = 0 ]; then
			echoG "Domain ${MY_DOMAIN2} exists, deleting..."        
			rm_ols_vh_conf
			rm_dm_ols_svr_conf ${MY_DOMAIN2}
			restart_lsws
			echoG "Domain remove finished!"
		else 
			echoR "Domain does not found, exit!"    
		fi
    fi

}

archive_main_dir(){
	
	# create archive
	if [[ ! -e "${WWW_PATH}/deleted" ]]; then mkdir -p "${WWW_PATH}/deleted"; fi

	if [ "${MY_DOMAIN}" != '' ]; then
        if [ -d "${WWW_PATH}/${MY_DOMAIN}" ]; then
			echoG "Archiving virtual host config: ${WWW_PATH}/${MY_DOMAIN}"
			cd "${WWW_PATH}/${MY_DOMAIN}/www" && touch db.sql && rm *.sql && wp db export --allow-root && mv *.sql "${WWW_PATH}/${MY_DOMAIN}/backups/db.sql" && cd /tmp
			mv "${WWW_PATH}/${MY_DOMAIN}" "${WWW_PATH}/deleted/${MY_DOMAIN}"
		fi
    fi
    if [ "${MY_DOMAIN2}" != '' ]; then
        if [ -d "${WWW_PATH}/${MY_DOMAIN2}" ]; then
			echoG "Archiving virtual host config: ${WWW_PATH}/${MY_DOMAIN2} to ${WWW_PATH}/deleted/${MY_DOMAIN2}"
			cd "${WWW_PATH}/${MY_DOMAIN2}/www" && touch db.sql && rm *.sql && wp db export --allow-root && mv *.sql "${WWW_PATH}/${MY_DOMAIN2}/backups/db.sql" && cd /tmp
			mv "${WWW_PATH}/${MY_DOMAIN2}" "${WWW_PATH}/deleted/${MY_DOMAIN2}"
		fi
    fi
	
}


verify_domain() {
	
	if [ "${MY_DOMAIN}" != '' ]; then
        curl -Is http://${MY_DOMAIN}/ | grep -i LiteSpeed >/dev/null 2>&1
		if [ ${?} = 0 ]; then
			echoG "${MY_DOMAIN} check PASS"
		else
			echoR "${MY_DOMAIN} inaccessible, skip!"
			DOMAIN_PASS='OFF'
		fi
    fi
    if [ "${MY_DOMAIN2}" != '' ]; then
        curl -Is http://${MY_DOMAIN2}/ | grep -i LiteSpeed >/dev/null 2>&1
		if [ ${?} = 0 ]; then
			echoG "${MY_DOMAIN2} check PASS"
		else
			echoR "${MY_DOMAIN2} inaccessible, skip!"
			DOMAIN_PASS='OFF'
		fi
    fi
}
input_email() {
    if [[ ! ${EMAIL} =~ ${CKREG} ]]; then
    	echoR "\nPlease enter a valid E-mail, skip!\n"
        EMAIL_SKIP='ON'
    fi	
}
apply_lecert() {
    
	if [ "${MY_DOMAIN2}" != '' ]; then
        certbot certonly --expand --agree-tos --non-interactive --keep-until-expiring --rsa-key-size 2048 -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} -d ${MY_DOMAIN2}
		echoB "certbot certonly --expand --agree-tos --non-interactive --keep-until-expiring --rsa-key-size 2048 -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} -d ${MY_DOMAIN2}"
    else
        certbot certonly --expand --agree-tos --non-interactive --keep-until-expiring --rsa-key-size 2048 -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} 
		echoB "certbot certonly --expand --agree-tos --non-interactive --keep-until-expiring --rsa-key-size 2048 -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} "
    fi
	
    if [ ${?} -eq 0 ]; then
        update_ssl_vh_conf    
    else
        echoR "Oops, something went wrong..."
        exit 1
    fi
}

certbothook() {
    grep 'certbot.*restart lsws' ${BOTCRON} >/dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG 'Web Server Restart hook already set!'
    else
        if [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ] ; then
            sed -i 's/0.*/&  --deploy-hook "systemctl restart lsws"/g' ${BOTCRON}
        elif [ "${OSNAME}" = 'centos' ]; then
            if [ "${OSVER}" = '7' ]; then
                echo "0 0,12 * * * root python -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q --deploy-hook 'systemctl restart lsws'" \
                | sudo tee -a /etc/crontab > /dev/null
            elif [ "${OSVER}" = '8' ]; then
                echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && /usr/local/bin/certbot renew -q --deploy-hook 'systemctl restart lsws'" \
                | sudo tee -a /etc/crontab > /dev/null
            else
                echoY 'Please check certbot crontab'
            fi
        fi    
        grep 'restart lsws' ${BOTCRON} > /dev/null 2>&1
        if [ ${?} = 0 ]; then 
            echoG 'Certbot hook update success'
        else 
            echoY 'Please check certbot crond'
        fi
    fi
}

check_empty(){
    if [ -z "${1}" ]; then
        echoR "\nPlease input a value! exit!\n"
        exit 1
    fi
}

domain_input(){
    check_empty ${MY_DOMAIN}
    check_duplicate ${MY_DOMAIN} ${WEBCF}
    if [ ${?} = 0 ]; then
        echoR "domain existed, skip!"
        DOMAIN_SKIP='ON'
    fi
}

issue_cert(){
    if [ ${ISSUECERT} = 'ON' ]; then
        verify_domain
        if [ ${DOMAIN_PASS} = 'ON' ]; then
            input_email
            if [ ${EMAIL_SKIP} = 'OFF' ]; then
                apply_lecert
                certbothook
            fi    
        else
            show_help 2   
        fi    
    fi
}

end_msg(){
    echoG 'Setup finished!'
}    

main() {
    check_root
    check_provider
    check_home_path
    check_os
    check_php_version
	install_wp_cli
    domain_input
    check_webserver 
    main_set_vh ${MY_DOMAIN}
	restart_lsws
    issue_cert
	restart_lsws
    check_install_wp
    end_msg
}

main_delete(){
    check_webserver
    check_empty ${1}
    rm_le_cert
    rm_main_conf
	archive_main_dir
	restart_lsws
}

while [ ! -z "${1}" ]; do
    case $1 in
        -d1 | -D1 | --domain1) shift
            if [ "${1}" = '' ]; then
                echoR "\nPlease enter a valid primary domain, exit!\n"   
                exit 1
            else
                MY_DOMAIN="${1}"
            fi
        ;;
		-d2 | -D2 | --domain2) shift
            if [ "${1}" = '' ]; then
                MY_DOMAIN2=""
            else
                MY_DOMAIN2="${1}"
            fi
        ;;
        -le | -LE | --letsencrypt) shift
            if [ "${1}" = '' ] || [[ ! ${1} =~ ${CKREG} ]]; then
                echoR "\nPlease enter a valid E-mail, exit!\n"   
                exit 1
            else
                ISSUECERT='ON'
                EMAIL="${1}"
            fi
        ;;   
        --wpinstall)
            WORDPRESS='ON'
        ;;
		--user) shift
            if [ "${1}" = '' ]; then
                show_help 1
            else
                USER="${1}"
                GROUP="${1}"
            fi
        ;;
		--pwsftp) shift
            if [ "${1}" = '' ]; then
                PWSFTP=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
            else
                PWSFTP="${1}"
            fi
        ;;
		--pwsql) shift
            if [ "${1}" = '' ]; then
                PWSQL=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
            else
                PWSQL="${1}"
            fi
        ;;
		--pwwp) shift
            if [ "${1}" = '' ]; then
                PWWPADMIN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
            else
                PWWPADMIN="${1}"
            fi
        ;;
		--lsphp )           
                check_value_follow "$2" "LSPHP version"
                shift
                cnt=${#LSPHPVERLIST[@]}
                for (( i = 0 ; i < cnt ; i++ )); do
                    if [ "$1" = "${LSPHPVERLIST[$i]}" ] ; then LSPHPVER=$1; fi
                done
                ;;
        --delete) shift
            if [ "${1}" = '' ]; then
                show_help 1
            else
                MY_DOMAIN="${1}"
                main_delete "${MY_DOMAIN}"
                exit 0
            fi
        ;; 
		--help)
            show_help 1
        ;;
        *)
            echoR "unknown argument..."
            show_help 1
        ;;
    esac
    shift
done
main
exit 0