#!/bin/bash

##############################################################################
#    Open LiteSpeed + MariaDB setup                                          #
#    Author: Raul Peixoto, WP Raiser                                         #
#    Based on: LiteSpeed 1-Click Install OLS                                 #
##############################################################################

# variables
TEMPRANDSTR=
OSNAMEVER=UNKNOWN
OSNAME=
OSVER=
OSTYPE=$(uname -m)
MARIADBCPUARCH=
SERVER_ROOT=/usr/local/lsws
WEBCF="$SERVER_ROOT/conf/httpd_config.conf"
OLSINSTALLED=
MYSQLINSTALLED=
TESTGETERROR=no
DATABASENAME=olsdbname
USERNAME=olsdbuser
DBPREFIX=wp_
VERBOSE=0
PWD_FILE=$SERVER_ROOT/password
WPPORT=80
SSLWPPORT=443
FORCEYES=0
SITEDOMAIN=*
EMAIL=
ADMINPASSWORD=
ROOTPASSWORD=
USERPASSWORD=
LSPHPVERLIST=(71 72 73 74 80 81)
MARIADBVERLIST=(10.2 10.3 10.4 10.5 10.6 10.7 10.8 10.9)
LSPHPVER=80
MARIADBVER=10.6
WEBADMIN_LSPHPVER=80
ALLERRORS=0
TEMPPASSWORD=
ACTION=INSTALL
FOLLOWPARAM=
CONFFILE=myssl.conf
EPACE='        '
FPACE='    '
APT='apt-get -qq'
YUM='yum -q'
SERVERIP=$(/usr/bin/curl -s https://ifconfig.me)

function echoY
{
    FLAG=$1
    shift
    echo -e "\033[38;5;148m$FLAG\033[39m$@"
}

function echoG
{
    FLAG=$1
    shift
    echo -e "\033[38;5;71m$FLAG\033[39m$@"
}

function echoB
{
    FLAG=$1
    shift
    echo -e "\033[38;1;34m$FLAG\033[39m$@"
}

function echoR
{
    FLAG=$1
    shift
    echo -e "\033[38;5;203m$FLAG\033[39m$@"
}

function echoW
{
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}

function echoNW
{
    FLAG=${1}
    shift
    echo -e "\033[1m${FLAG}\033[0m${@}"
}

function echoCYAN
{
    FLAG=$1
    shift
    echo -e "\033[1;36m$FLAG\033[0m$@"
}

function silent
{
    if [ "${VERBOSE}" = '1' ] ; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

function change_owner
{
    chown -R ${USER}:${GROUP} ${1}
}

function check_root
{
    local INST_USER=`id -u`
    if [ $INST_USER != 0 ] ; then
        echoR "Sorry, only the root user can install."
        echo
        exit 1
    fi
}

function update_system(){
    echoG 'System update'
    if [ "$OSNAME" = "centos" ] ; then
        silent ${YUM} update -y >/dev/null 2>&1
    else
        silent ${APT} update && ${APT} upgrade -y >/dev/null 2>&1
    fi
}

function check_wget
{
    which wget  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install wget
        else
            ${APT} -y install wget
        fi

        which wget  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during wget installation."
            ALLERRORS=1
        fi
    fi
}

function check_curl
{
    which curl  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install curl
        else
            ${APT} -y install curl
        fi

        which curl  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during curl installation."
            ALLERRORS=1
        fi
    fi
}

function check_firewall
{
   
# reinstall and reset firewall
apt purge -y ufw
iptables --flush
iptables --delete-chain
apt install -y ufw
echo "y" | ufw reset

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

# if needed
#ufw allow 3306/tcp   # mysql
#ufw allow 6379/tcp   # redis
#ufw allow 11211/tcp  # memcached

# save and enable
echo "y" | ufw enable
ufw status verbose

}

function check_server
{

# basic settings
dpkg-reconfigure -f noninteractive tzdata
locale-gen en_US en_US.utf8
localectl set-locale LANG=en_US.utf8
update-locale LC_ALL=en_US.utf8
echo "SELECTED_EDITOR=\"/bin/nano\"" > /root/.selected_editor
grep -qxF '127.0.0.1 localhost' /etc/hosts || echo "127.0.0.1 localhost" >> /etc/hosts
grep -qxF "* soft nofile 999999" /etc/security/limits.conf || echo "* soft nofile 999999" >> /etc/security/limits.conf
grep -qxF "* hard nofile 999999" /etc/security/limits.conf || echo "* hard nofile 999999" >> /etc/security/limits.conf

# Add 2GB swap if needed
if [[ "$TOTALSWAP" != "2" ]]; then
	printf "${BGREEN}Creating Swap... ${BNC} \n"
    swapoff -a && sed -i '/swap/d' /etc/fstab
    dd if=/dev/zero of=/swapfile bs=1024 count=2097152
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
	grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo -e "/swapfile none swap sw 0 0 \n" >> /etc/fstab
else
	echo "2GB SWAP already exists."
fi

# aliases
alias wget2='aria2c --split=8 --min-split-size=5M --connect-timeout=5 --timeout=7 --lowest-speed-limit=10K --max-connection-per-server=10 --max-tries=3 --retry-wait=5 --allow-overwrite=true'

# trim and remove comments
sed -i 's:^#.*$::g' /etc/security/limits.conf
sed -i '/^$/d' /etc/security/limits.conf
sed -i 's:^#.*$::g' /etc/fstab
sed -i '/^$/d' /etc/fstab

}


function check_packages
{
	# certbot
	which certbot  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install certbot
        else
            ${APT} -y install certbot
        fi

        which certbot  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during certbot installation."
            ALLERRORS=1
        fi
    fi

	# pv
	which pv  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install pv
        else
            ${APT} -y install pv
        fi

        which pv  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during pv installation."
            ALLERRORS=1
        fi
    fi

	# pigz
	which pigz  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install pigz
        else
            ${APT} -y install pigz
        fi

        which pigz  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during pigz installation."
            ALLERRORS=1
        fi
    fi
	
	# pigz
	which zip  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install zip
        else
            ${APT} -y install zip
        fi

        which zip  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during zip installation."
            ALLERRORS=1
        fi
    fi
	
	# memcached
	which memcached  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install memcached
        else
            ${APT} -y install memcached
        fi

        which memcached  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during memcached installation."
            ALLERRORS=1
        fi
    fi
	
	# redis
	which redis-cli  >/dev/null 2>&1
    if [ $? != 0 ] ; then
        if [ "$OSNAME" = "centos" ] ; then
            silent ${YUM} -y install redis
        else
            ${APT} -y install redis-server
        fi

        which redis-cli  >/dev/null 2>&1
        if [ $? != 0 ] ; then
            echoR "An error occurred during redis installation."
            ALLERRORS=1
        fi
    fi
	

# memcached config
cat << EOF > /etc/memcached.conf
-d
logfile /var/log/memcached.log
-m 1024
-p 11211
-u memcache
-l 127.0.0.1
-P /var/run/memcached/memcached.pid
EOF

# redis config
cat << EOF > /etc/redis/redis.conf
bind 127.0.0.1
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize yes
supervised no
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
always-show-logo yes
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
slave-serve-stale-data yes
slave-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
slave-priority 100
maxmemory 1024mb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
slave-lazy-flush no
appendonly no
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble no
lua-time-limit 5000
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 0
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit slave 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
aof-rewrite-incremental-fsync yes
EOF

}

function update_email
{
    if [ "$EMAIL" = '' ] ; then
        if [ "$SITEDOMAIN" = "*" ] ; then
            EMAIL=root@localhost
        else
            EMAIL=root@$SITEDOMAIN
        fi
    fi
}

function restart_lsws
{
    systemctl stop lsws >/dev/null 2>&1
    systemctl start lsws
}

function usage
{
    echo -e "\033[1mOPTIONS\033[0m"
    echoNW "  -A,    --adminpassword [PASSWORD]" "${EPACE}To set the WebAdmin password for OpenLiteSpeed instead of using a random one."
    echoNW "  -E,    --email [EMAIL]          " "${EPACE} To set the administrator email."
    echoW " --lsphp [VERSION]                 " "To set the LSPHP version, such as 81. We currently support versions '${LSPHPVERLIST[@]}'."
    echoW " --mariadbver [VERSION]            " "To set MariaDB version, such as 10.6. We currently support versions '${MARIADBVERLIST[@]}'."
    echoNW "  -R,    --dbrootpassword [PASSWORD]  " "     To set the database root password instead of using a random one."
    echoW " --listenport [PORT]               " "To set the HTTP server listener port, default is 80."
    echoW " --ssllistenport [PORT]            " "To set the HTTPS server listener port, default is 443."
    echoNW "  -U,    --uninstall              " "${EPACE} To uninstall OpenLiteSpeed and remove installation directory."
    echoNW "  -P,    --purgeall               " "${EPACE} To uninstall OpenLiteSpeed, remove installation directory, and purge all data in MySQL."
    echoNW "  -Q,    --quiet                  " "${EPACE} To use quiet mode, won't prompt to input anything."
    echoNW "  -V,    --version                " "${EPACE} To display the script version information."
    echoNW "  -v,    --verbose                " "${EPACE} To display more messages during the installation."
    echoNW "  -H,    --help                   " "${EPACE} To display help messages."
    echo 
    echo -e "\033[1mEXAMPLES\033[0m"
    echoW "./ols1clk.sh -A 'adminpass' -E root@localhost --lsphp 74 --mariadbver 10.6 --dbrootpassword mysqlpass --verbose            " "To install OpenLiteSpeed and MariaDB."
    echo
    exit 0
}

function display_license
{
    echoY '**********************************************************************************************'
    echoY '*                    Open LiteSpeed One click setup for WordPress                            *'
    echoY '*                    Copyright (C) 2016 - 2022 WP Raiser.                                    *'
    echoY '**********************************************************************************************'
}

function check_os
{
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='nobody'
        GROUP='nobody'
        case $(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1) in 
        6)
            OSNAMEVER=CENTOS6
            OSVER=6
            ;;
        7)
            OSNAMEVER=CENTOS7
            OSVER=7
            ;;
        8)
            OSNAMEVER=CENTOS8
            OSVER=8
            ;;
        esac    
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        USER='nobody'
        GROUP='nogroup'
        case $(cat /etc/os-release | grep UBUNTU_CODENAME | cut -d = -f 2) in
        trusty)
            OSNAMEVER=UBUNTU14
            OSVER=trusty
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
            ;;
        xenial)
            OSNAMEVER=UBUNTU16
            OSVER=xenial
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
            ;;
        bionic)
            OSNAMEVER=UBUNTU18
            OSVER=bionic
            MARIADBCPUARCH="arch=amd64"
            ;;
        focal)            
            OSNAMEVER=UBUNTU20
            OSVER=focal
            MARIADBCPUARCH="arch=amd64"
            ;;
        jammy)            
            OSNAMEVER=UBUNTU22
            OSVER=jammy
            MARIADBCPUARCH="arch=amd64"
            ;;            
        esac
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        case $(cat /etc/os-release | grep VERSION_CODENAME | cut -d = -f 2) in
        wheezy)
            OSNAMEVER=DEBIAN7
            OSVER=wheezy
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        jessie)
            OSNAMEVER=DEBIAN8
            OSVER=jessie
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        stretch) 
            OSNAMEVER=DEBIAN9
            OSVER=stretch
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        buster)
            OSNAMEVER=DEBIAN10
            OSVER=buster
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        bullseye)
            OSNAMEVER=DEBIAN11
            OSVER=bullseye
            MARIADBCPUARCH="arch=amd64,i386"
            ;;
        esac    
    fi

    if [ "$OSNAMEVER" = '' ] ; then
        echoR "Sorry, currently one click installation only supports Centos(6-8), Debian(7-11) and Ubuntu(14,16,18,20,22)."
        exit 1
    else
        if [ "$OSNAME" = "centos" ] ; then
            echoG "Current platform is "  "$OSNAME $OSVER."
        else
            export DEBIAN_FRONTEND=noninteractive
            echoG "Current platform is "  "$OSNAMEVER $OSNAME $OSVER."
        fi
    fi
}

function update_centos_hashlib
{
    if [ "$OSNAME" = 'centos' ] ; then
        silent ${YUM} -y install python-hashlib
    fi
}

function install_ols_centos
{
    local action=install
    if [ "$1" = "Update" ] ; then
        action=update
    elif [ "$1" = "Reinstall" ] ; then
        action=reinstall
    fi

    local JSON=
    if [ "x$LSPHPVER" = "x70" ] || [ "x$LSPHPVER" = "x71" ] || [ "x$LSPHPVER" = "x72" ] || [ "x$LSPHPVER" = "x73" ] || [ "x$LSPHPVER" = "x74" ]; then
        JSON=lsphp$LSPHPVER-json
    fi
    echoB "${FPACE} - add epel repo"
    silent ${YUM} -y $action epel-release
    echoB "${FPACE} - add litespeedtech repo"
    rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el$OSVER.noarch.rpm >/dev/null 2>&1
    echoB "${FPACE} - $1 OpenLiteSpeed"
    silent ${YUM} -y $action openlitespeed
    if [ ! -e $SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp ] ; then
        action=install
    fi
    echoB "${FPACE} - $1 lsphp$LSPHPVER"
    if [ "$action" = "reinstall" ] ; then
        silent ${YUM} -y remove lsphp$LSPHPVER-mysqlnd
    fi
    silent ${YUM} -y install lsphp$LSPHPVER-mysqlnd
    if [[ "$LSPHPVER" == 8* ]]; then 
        silent ${YUM} -y $action lsphp$LSPHPVER lsphp$LSPHPVER-common lsphp$LSPHPVER-gd lsphp$LSPHPVER-process lsphp$LSPHPVER-mbstring \
        lsphp$LSPHPVER-xml lsphp$LSPHPVER-pdo lsphp$LSPHPVER-imap lsphp$LSPHPVER-curl lsphp$LSPHPVER-imagick lsphp$LSPHPVER-intl lsphp$LSPHPVER-memcached lsphp$LSPHPVER-opcache lsphp$LSPHPVER-redis
    else
        silent ${YUM} -y $action lsphp$LSPHPVER lsphp$LSPHPVER-common lsphp$LSPHPVER-gd lsphp$LSPHPVER-process lsphp$LSPHPVER-mbstring \
        lsphp$LSPHPVER-xml lsphp$LSPHPVER-mcrypt lsphp$LSPHPVER-pdo lsphp$LSPHPVER-imap lsphp$LSPHPVER-curl lsphp$LSPHPVER-imagick lsphp$LSPHPVER-intl lsphp$LSPHPVER-memcached lsphp$LSPHPVER-opcache lsphp$LSPHPVER-redis $JSON
    fi
    if [ $? != 0 ] ; then
        echoR "An error occurred during OpenLiteSpeed installation."
        ALLERRORS=1
    else
        echoB "${FPACE} - Setup lsphp symlink"
        ln -sf $SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp $SERVER_ROOT/fcgi-bin/lsphpnew
        sed -i -e "s/fcgi-bin\/lsphp/fcgi-bin\/lsphpnew/g" "${WEBCF}"
        sed -i -e "s/lsphp${WEBADMIN_LSPHPVER}\/bin\/lsphp/lsphp$LSPHPVER\/bin\/lsphp/g" "${WEBCF}"
        if [ ! -f /usr/bin/php ]; then
            ln -s ${SERVER_ROOT}/lsphp${LSPHPVER}/bin/php /usr/bin/php
        fi          
    fi
	
}

function uninstall_ols_centos
{
    echoB "${FPACE} - Remove OpenLiteSpeed"
    silent ${YUM} -y remove openlitespeed
    if [ $? != 0 ] ; then
        echoR "An error occurred while uninstalling OpenLiteSpeed."
        ALLERRORS=1
    fi
    rm -rf $SERVER_ROOT/
}

function uninstall_php_centos
{
    ls "${SERVER_ROOT}" | grep lsphp >/dev/null
    if [ $? = 0 ] ; then
        local LSPHPSTR="$(ls ${SERVER_ROOT} | grep -i lsphp | tr '\n' ' ')"
        for LSPHPVER in ${LSPHPSTR}; do 
            echoB "${FPACE} - Detect LSPHP version $LSPHPVER"
            if [ "$LSPHPVER" = "lsphp80" ]; then
                silent ${YUM} -y remove lsphp$LSPHPVER lsphp$LSPHPVER-common lsphp$LSPHPVER-gd lsphp$LSPHPVER-process lsphp$LSPHPVER-mbstring \
                lsphp$LSPHPVER-mysqlnd lsphp$LSPHPVER-xml  lsphp$LSPHPVER-pdo lsphp$LSPHPVER-imap lsphp$LSPHPVER-curl lsphp$LSPHPVER-imagick lsphp$LSPHPVER-intl lsphp$LSPHPVER-memcached lsphp$LSPHPVER-opcache lsphp$LSPHPVER-redis lsphp*
            else
                silent ${YUM} -y remove lsphp$LSPHPVER lsphp$LSPHPVER-common lsphp$LSPHPVER-gd lsphp$LSPHPVER-process lsphp$LSPHPVER-mbstring \
                lsphp$LSPHPVER-mysqlnd lsphp$LSPHPVER-xml lsphp$LSPHPVER-mcrypt lsphp$LSPHPVER-pdo lsphp$LSPHPVER-imap lsphp$LSPHPVER-curl lsphp$LSPHPVER-imagick lsphp$LSPHPVER-intl lsphp$LSPHPVER-memcached lsphp$LSPHPVER-opcache lsphp$LSPHPVER-redis $JSON lsphp*
            fi                
            if [ $? != 0 ] ; then
                echoR "An error occurred while uninstalling lsphp$LSPHPVER"
                ALLERRORS=1
            fi
        done 
    else
        echoB "${FPACE} - Uninstall LSPHP"
        ${YUM} -y remove lsphp*
        echoR "Uninstallation cannot get the currently installed LSPHP version."
        echoY "May not uninstall LSPHP correctly."
        LSPHPVER=
    fi
}

function install_ols_debian
{
    local action=
    local INSTALL_STATUS=0
    if [ "$1" = "Update" ] ; then
        action="--only-upgrade"
    elif [ "$1" = "Reinstall" ] ; then
        action="--reinstall"
    fi
    echoB "${FPACE} - add litespeedtech repo"
    grep -Fq  "http://rpms.litespeedtech.com/debian/" /etc/apt/sources.list.d/lst_debian_repo.list 2>/dev/null
    if [ $? != 0 ] ; then
        echo "deb http://rpms.litespeedtech.com/debian/ $OSVER main"  > /etc/apt/sources.list.d/lst_debian_repo.list
    fi

    wget -qO /etc/apt/trusted.gpg.d/lst_debian_repo.gpg http://rpms.litespeedtech.com/debian/lst_debian_repo.gpg
    wget -qO /etc/apt/trusted.gpg.d/lst_repo.gpg http://rpms.litespeedtech.com/debian/lst_repo.gpg
    echoB "${FPACE} - update list"
    ${APT} -y update
    echoB "${FPACE} - $1 OpenLiteSpeed"
    silent ${APT} -y install $action openlitespeed

    if [ ${?} != 0 ] ; then
        echoR "An error occurred during OpenLiteSpeed installation."
        ALLERRORS=1
        INSTALL_STATUS=1
    fi
    if [ ! -e $SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp ] ; then
        action=
    fi
    echoB "${FPACE} - $1 lsphp$LSPHPVER"
    silent ${APT} -y install $action lsphp$LSPHPVER lsphp$LSPHPVER-mysql lsphp$LSPHPVER-imap lsphp$LSPHPVER-curl lsphp$LSPHPVER-imagick lsphp$LSPHPVER-intl lsphp$LSPHPVER-memcached lsphp$LSPHPVER-opcache lsphp$LSPHPVER-redis

    if [ $? != 0 ] ; then
        echoR "An error occurred during lsphp$LSPHPVER installation."
        ALLERRORS=1
    fi
    
    if [ -e $SERVER_ROOT/bin/openlitespeed ]; then 
        echoB "${FPACE} - Setup lsphp symlink"
        ln -sf $SERVER_ROOT/lsphp$LSPHPVER/bin/lsphp $SERVER_ROOT/fcgi-bin/lsphpnew
        sed -i -e "s/fcgi-bin\/lsphp/fcgi-bin\/lsphpnew/g" "${WEBCF}"    
        sed -i -e "s/lsphp${WEBADMIN_LSPHPVER}\/bin\/lsphp/lsphp$LSPHPVER\/bin\/lsphp/g" "${WEBCF}"
        if [ ! -f /usr/bin/php ]; then
            ln -s ${SERVER_ROOT}/lsphp${LSPHPVER}/bin/php /usr/bin/php
        fi        
    fi
	
}


function uninstall_ols_debian
{
    echoB "${FPACE} - Uninstall OpenLiteSpeed"
    silent ${APT} -y purge openlitespeed
    silent ${APT} -y remove openlitespeed
    ${APT} clean
    #rm -rf $SERVER_ROOT/
}

function uninstall_php_debian
{
    echoB "${FPACE} - Uninstall LSPHP"
    silent ${APT} -y --purge remove lsphp*
    if [ -e /usr/bin/php ] && [ -L /usr/bin/php ]; then 
        rm -f /usr/bin/php
    fi
}

function action_uninstall
{
    if [ "$ACTION" = "UNINSTALL" ] ; then
        uninstall_warn
        uninstall
        uninstall_result
        exit 0
    fi    
} 

function action_purgeall
{    
    if [ "$ACTION" = "PURGEALL" ] ; then
        uninstall_warn
        if [ "$ROOTPASSWORD" = '' ] ; then
            passwd=
            echoY "Please input the MySQL root password: "
            read passwd
            ROOTPASSWORD=$passwd
        fi
        uninstall
        purgedatabase
        uninstall_result
        exit 0
    fi
}

function random_password
{
    if [ ! -z ${1} ]; then 
        TEMPPASSWORD="${1}"
    else    
        TEMPPASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 ; echo '')
    fi
}

function random_strong_password
{
    if [ ! -z ${1} ]; then 
        TEMPPASSWORD="${1}"
    else    
        TEMPPASSWORD=$(openssl rand -base64 32 | head -c 32)
    fi
}

function main_gen_password
{
    random_password "${ADMINPASSWORD}"
    ADMINPASSWORD="${TEMPPASSWORD}"
    random_strong_password "${ROOTPASSWORD}"
    ROOTPASSWORD="${TEMPPASSWORD}"
    random_strong_password "${USERPASSWORD}"
    USERPASSWORD="${TEMPPASSWORD}"
    random_password "${WPPASSWORD}"
    WPPASSWORD="${TEMPPASSWORD}"
    read_password "$ADMINPASSWORD" "webAdmin password"
    ADMINPASSWORD=$TEMPPASSWORD
}

function main_ols_password
{
    echo "WebAdmin username is [admin], password is [$ADMINPASSWORD]." >> ${PWD_FILE}
	echo "$ADMINPASSWORD]" > ${PWD_FILE}.admin
    set_ols_password
}

function test_mysql_password
{
    CURROOTPASSWORD=$ROOTPASSWORD
    TESTPASSWORDERROR=0

    mysqladmin -uroot -p$CURROOTPASSWORD password $CURROOTPASSWORD
    if [ $? != 0 ] ; then
        #Sometimes, mysql will treat the password error and restart will fix it.
        service mysql restart
        if [ $? != 0 ] && [ "$OSNAME" = "centos" ] ; then
            service mysqld restart
        fi

        mysqladmin -uroot -p$CURROOTPASSWORD password $CURROOTPASSWORD
        if [ $? != 0 ] ; then
            printf '\033[31mPlease input the current root password:\033[0m'
            read answer
            mysqladmin -uroot -p$answer password $answer
            if [ $? = 0 ] ; then
                CURROOTPASSWORD=$answer
            else
                echoR "root password is incorrect. 2 attempts remaining."
                printf '\033[31mPlease input the current root password:\033[0m'
                read answer
                mysqladmin -uroot -p$answer password $answer
                if [ $? = 0 ] ; then
                    CURROOTPASSWORD=$answer
                else
                    echoR "root password is incorrect. 1 attempt remaining."
                    printf '\033[31mPlease input the current root password:\033[0m'
                    read answer
                    mysqladmin -uroot -p$answer password $answer
                    if [ $? = 0 ] ; then
                        CURROOTPASSWORD=$answer
                    else
                        echoR "root password is incorrect. 0 attempts remaining."
                        echo
                        TESTPASSWORDERROR=1
                    fi
                fi
            fi
        fi
    fi

    export TESTPASSWORDERROR=$TESTPASSWORDERROR
    if [ "x$TESTPASSWORDERROR" = "x1" ] ; then
        export CURROOTPASSWORD=
    else
        export CURROOTPASSWORD=$CURROOTPASSWORD
    fi
}

function centos_install_mariadb
{
    echoB "${FPACE} - Add MariaDB repo"
    local REPOFILE=/etc/yum.repos.d/MariaDB.repo
    if [ ! -f $REPOFILE ] ; then
        local CENTOSVER=
        if [ "$OSTYPE" != "x86_64" ] ; then
            CENTOSVER=centos$OSVER-x86
        else
            CENTOSVER=centos$OSVER-amd64
        fi
        if [ "$OSNAMEVER" = "CENTOS8" ] ; then
            rpm --quiet --import https://downloads.mariadb.com/MariaDB/MariaDB-Server-GPG-KEY
            cat >> $REPOFILE <<END
[mariadb]
name = MariaDB
baseurl = https://downloads.mariadb.com/MariaDB/mariadb-$MARIADBVER/yum/rhel/\$releasever/\$basearch
gpgkey = file:///etc/pki/rpm-gpg/MariaDB-Server-GPG-KEY
gpgcheck=1
enabled = 1
module_hotfixes = 1
END
        else
            cat >> $REPOFILE <<END
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/$MARIADBVER/$CENTOSVER
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1

END
        fi 
    fi
    echoB "${FPACE} - Install MariaDB"
    if [ "$OSNAMEVER" = "CENTOS8" ] ; then
        silent ${YUM} install -y boost-program-options
        silent ${YUM} --disablerepo=AppStream install -y MariaDB-server MariaDB-client
    else
        silent ${YUM} -y install MariaDB-server MariaDB-client
    fi
    if [ $? != 0 ] ; then
        echoR "An error occurred during installation of MariaDB. Please fix this error and try again."
        echoR "You may want to manually run the command '${YUM} -y install MariaDB-server MariaDB-client' to check. Aborting installation!"
        exit 1
    fi
    echoB "${FPACE} - Start MariaDB"
    if [ "$OSNAMEVER" = "CENTOS8" ] || [ "$OSNAMEVER" = "CENTOS7" ] ; then
        silent systemctl enable mariadb
        silent systemctl start  mariadb
    else
        service mysql start
    fi    
}

function debian_install_mariadb
{
    echoB "${FPACE} - Install software properties"
	silent ${APT} -y -f install software-properties-common apt-transport-https curl gnupg2
		
    echoB "${FPACE} - Add MariaDB repo"
	curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-$MARIADBVER"
				
    echoB "${FPACE} - Update packages"
    ${APT} update
    echoB "${FPACE} - Install MariaDB"
    silent ${APT} -y -f --allow-unauthenticated install mariadb-server
    if [ $? != 0 ] ; then
        echoR "An error occurred during installation of MariaDB. Please fix this error and try again."
        echoR "You may want to manually run the command 'apt-get -y -f --allow-unauthenticated install mariadb-server' to check. Aborting installation!"
        exit 1
    fi
    echoB "${FPACE} - Start MariaDB"
    service mysql start
}

function install_mariadb
{
    echoG "Start Install MariaDB"
    if [ "$OSNAME" = 'centos' ] ; then
        centos_install_mariadb
    else
        debian_install_mariadb
	fi
		
    if [ $? != 0 ] ; then
        echoR "An error occurred when starting the MariaDB service. "
        echoR "Please fix this error and try again. Aborting installation!"
        exit 1
    fi

    echoB "${FPACE} - Set MariaDB root"
    mysql -uroot -e "flush privileges;"
    mysqladmin -uroot password $ROOTPASSWORD
    if [ $? = 0 ] ; then
        CURROOTPASSWORD=$ROOTPASSWORD
    else
        #test it is the current password
        mysqladmin -uroot -p$ROOTPASSWORD password $ROOTPASSWORD
        if [ $? = 0 ] ; then
            #echoG "MySQL root password is $ROOTPASSWORD"
            CURROOTPASSWORD=$ROOTPASSWORD
        else
            echoR "Failed to set MySQL root password to $ROOTPASSWORD, it may already have a root password."
            printf '\033[31mInstallation must know the password for the next step.\033[0m'
            test_mysql_password

            if [ "$TESTPASSWORDERROR" = "1" ] ; then
                echoY "If you forget your password you may stop the mysqld service and run the following command to reset it,"
                echoY "mysqld_safe --skip-grant-tables &"
                echoY "mysql --user=root mysql"
                echoY "update user set Password=PASSWORD('new-password') where user='root'; flush privileges; exit; "
                echoR "Aborting installation."
                echo
                exit 1
            fi

            if [ "$CURROOTPASSWORD" != "$ROOTPASSWORD" ] ; then
                echoY "Current MySQL root password is $CURROOTPASSWORD, it will be changed to $ROOTPASSWORD."
                printf '\033[31mDo you still want to change it?[y/N]\033[0m '
                read answer
                echo

                if [ "$answer" != "Y" ] && [ "$answer" != "y" ] ; then
                    echoG "OK, MySQL root password not changed."
                    ROOTPASSWORD=$CURROOTPASSWORD
                else
                    mysqladmin -uroot -p$CURROOTPASSWORD password $ROOTPASSWORD
                    if [ $? = 0 ] ; then
                        echoG "OK, MySQL root password changed to $ROOTPASSWORD."
                    else
                        echoR "Failed to change MySQL root password, it is still $CURROOTPASSWORD."
                        ROOTPASSWORD=$CURROOTPASSWORD
                    fi
                fi
            fi
        fi
    fi
    save_db_root_pwd
    echoG "End Install MariaDB"
	
# mysql settings
echoB "${FPACE} - Configuring MariaDB"

cat >"/etc/mysql/my.cnf" <<EOL
# For explanations see
# http://dev.mysql.com/doc/mysql/en/server-system-variables.html

[mysqld]
user                           = mysql
pid-file                       = /var/run/mysqld/mysqld.pid
socket                         = /var/run/mysqld/mysqld.sock
port                           = 3306
bind-address                   = 127.0.0.1
explicit_defaults_for_timestamp
secure-file-priv               = ""
skip-log-bin
sql_mode                       = NO_ENGINE_SUBSTITUTION
skip-name-resolve              = 0

# LOGGING #
log-error                      = /var/log/mysql/mysql-error.log
log-queries-not-using-indexes  = 0
slow-query-log                 = 1
long_query_time                = 10
slow-query-log-file            = /var/log/mysql/mysql-slow.log

# SAFETY #
max-allowed-packet             = 1G
sysdate-is-now                 = 1
max-connect-errors             = 1000000
max_connections                = 1000

# OTHER #
max_heap_table_size            = 32M
tmp_table_size                 = 32M

# MySQL 8+ #
join_buffer_size               = 16M
sort_buffer_size               = 16M

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-flush-log-at-trx-commit = 2
innodb-file-per-table          = 1
innodb_buffer_pool_instances   = 2
innodb_buffer_pool_size        = 3G
innodb_log_file_size           = 256M
innodb_io_capacity             = 400
innodb_io_capacity_max         = 2000

EOL


	# restart
	service $MYSQLNAME restart
    echoG "End Configuring MariaDB"
}

function resetmysqlroot
{
    if [ "x$OSNAMEVER" = "xCENTOS8" ]; then
        MYSQLNAME='mariadb'
    else
        MYSQLNAME=mysql
    fi
    service $MYSQLNAME stop
    if [ $? != 0 ] && [ "x$OSNAME" = "xcentos" ] ; then
        service $MYSQLNAME stop
    fi

    DEFAULTPASSWD=$1

    echo "update user set Password=PASSWORD('$DEFAULTPASSWD') where user='root'; flush privileges; exit; " > /tmp/resetmysqlroot.sql
    mysqld_safe --skip-grant-tables &
    #mysql --user=root mysql < /tmp/resetmysqlroot.sql
    mysql --user=root mysql -e "update user set Password=PASSWORD('$DEFAULTPASSWD') where user='root'; flush privileges; exit; "
    sleep 1
    service $MYSQLNAME restart
}

function save_db_root_pwd
{
    echo "mysql root password is [$ROOTPASSWORD]" > ${PWD_FILE}
	echo "$ROOTPASSWORD" > ${PWD_FILE}.mysql
}

function pure_mariadb
{
    if [ "$MYSQLINSTALLED" = "0" ] ; then
        install_mariadb
        ROOTPASSWORD=$CURROOTPASSWORD
    else
        echoG 'MariaDB already exist, skip!'
    fi
}

function uninstall_result
{
    if [ "$ALLERRORS" != "0" ] ; then
        echoY "Some error(s) occurred. Please check these as you may need to manually fix them."
    fi
    echoCYAN 'End OpenLiteSpeed one click Uninstallation << << << << << << <<'
}


function install_openlitespeed
{
    echoG "Start setup OpenLiteSpeed"
    local STATUS=Install
    if [ "$OLSINSTALLED" = "1" ] ; then
        OLS_VERSION=$(cat "$SERVER_ROOT"/VERSION)
        wget -qO "$SERVER_ROOT"/release.tmp  http://open.litespeedtech.com/packages/release?ver=$OLS_VERSION
        LATEST_VERSION=$(cat "$SERVER_ROOT"/release.tmp)
        rm "$SERVER_ROOT"/release.tmp
        if [ "$OLS_VERSION" = "$LATEST_VERSION" ] ; then
            STATUS=Reinstall
            echoY "OpenLiteSpeed is already installed with the latest version, will attempt to reinstall it."
        else
            STATUS=Update
            echoY "OpenLiteSpeed is already installed and newer version is available, will attempt to update it."
        fi
    fi

    if [ "$OSNAME" = "centos" ] ; then
        install_ols_centos $STATUS
    else
        install_ols_debian $STATUS
    fi
    silent killall -9 lsphp
    echoG "Ended seting up OpenLiteSpeed."
}


function gen_selfsigned_cert
{
    if [ -e $CONFFILE ] ; then
        source $CONFFILE 2>/dev/null
        if [ $? != 0 ]; then
            . $CONFFILE
        fi
    fi

cd $SERVER_ROOT/conf/
openssl genrsa -out server.key 2048
openssl req -new -x509 -key server.key -subj "/CN=server.local\/emailAddress=admin@server.local/C=US/ST=New Jersey/L=Virtual/O=OLS/OU=Server" -out server.crt -days 365
chmod 0600 server.key
chmod 0600 server.crt
cd /tmp

}


function set_ols_password
{
    ENCRYPT_PASS=`"$SERVER_ROOT/admin/fcgi-bin/admin_php" -q "$SERVER_ROOT/admin/misc/htpasswd.php" $ADMINPASSWORD`
    if [ $? = 0 ] ; then
        echo "admin:$ENCRYPT_PASS" > "$SERVER_ROOT/admin/conf/htpasswd"
        if [ $? = 0 ] ; then
            echoG "Set OpenLiteSpeed Web Admin access."
        else
            echoG "OpenLiteSpeed WebAdmin password not changed."
        fi
    fi
}

function config_server
{
    echoB "${FPACE} - Configuring OpenLiteSpeed"
    if [ -e "${WEBCF}" ] ; then

# web server settings, no domains
cat >${WEBCF} <<EOL
serverName                localhost
user                      nobody
group                     nogroup
priority                  0
enableLVE                 0
inMemBufSize              128M
swappingDir               /tmp/lshttpd/swap
autoFix503                1
enableh2c                 1
gracefulRestartTimeout    15
mime                      conf/mime.properties
showVersionNumber         0
useIpInProxyHeader        3
adminEmails               root@localhost

errorlog logs/error.log {
  logLevel                ERROR
  debugLevel              5
  rollingSize             128M
  keepDays                21
  compressArchive         1
  enableStderrLog         1
}

accesslog logs/access.log {
  rollingSize             256M
  keepDays                21
  compressArchive         0
}
indexFiles                index.html, index.php
autoIndex                 0

expires  {
  enableExpires           1
  expiresByType           image/*=A15552000,video/*=A15552000,text/css=A15552000,application/*=A15552000,font/*=A15552000
}
autoLoadHtaccess          1

tuning  {
  maxConnections          10000
  maxSSLConnections       10000
  connTimeout             300
  maxKeepAliveReq         10000
  keepAliveTimeout        7
  sndBufSize              0
  rcvBufSize              0
  maxReqURLLen            32768
  maxReqHeaderSize        65530
  maxReqBodySize          2G
  maxDynRespHeaderSize    32K
  maxDynRespSize          2G
  maxCachedFileSize       4096
  totalInMemCacheSize     32M
  maxMMapFileSize         256K
  totalMMapCacheSize      64M
  useSendfile             1
  fileETag                28
  enableGzipCompress      1
  compressibleTypes       default
  enableDynGzipCompress   1
  gzipCompressLevel       6
  gzipAutoUpdateStatic    1
  gzipStaticCompressLevel 6
  brStaticCompressLevel   6
  gzipMaxFileSize         10M
  gzipMinFileSize         256

  quicEnable              1
  quicShmDir              /dev/shm
}

fileAccessControl  {
  followSymbolLink        1
  checkSymbolLink         1
  forceStrictOwnership    1
  requiredPermissionMask  000
  restrictedPermissionMask 000
}

perClientConnLimit  {
  staticReqPerSec         10000
  dynReqPerSec            10000
  outBandwidth            0
  inBandwidth             0
  softLimit               10000
  hardLimit               10000
  blockBadReq             1
  gracePeriod             15
  banPeriod               60
}

CGIRLimit  {
  maxCGIInstances         20
  minUID                  11
  minGID                  10
  priority                0
  CPUSoftLimit            10
  CPUHardLimit            50
  memSoftLimit            1460M
  memHardLimit            1470M
  procSoftLimit           400
  procHardLimit           450
}

accessDenyDir  {
  dir                     /
  dir                     /etc/*
  dir                     /dev/*
  dir                     conf/*
  dir                     admin/conf/*
}

accessControl  {
  allow                   ALL, 173.245.48.0/20T, 103.21.244.0/22T, 103.22.200.0/22T, 103.31.4.0/22T, 141.101.64.0/18T, 108.162.192.0/18T, 190.93.240.0/20T, 188.114.96.0/20T, 197.234.240.0/22T, 198.41.128.0/17T, 162.158.0.0/15T, 104.16.0.0/13T, 104.24.0.0/14T, 172.64.0.0/13T, 131.0.72.0/22T, 2400:cb00::/32T, 2606:4700::/32T, 2803:f800::/32T, 2405:b500::/32T, 2405:8100::/32T, 2a06:98c0::/29T, 2c0f:f248::/32T
}

extprocessor lsphp {
  type                    lsapi
  address                 uds://tmp/lshttpd/lsphp.sock
  maxConns                64
  env                     PHP_LSAPI_CHILDREN=64
  env                     PHP_LSAPI_MAX_REQUESTS=500
  env                     LSAPI_AVOID_FORK=1
  initTimeout             60
  retryTimeout            0
  persistConn             1
  respBuffer              0
  autoStart               2
  path                    lsphp80/bin/lsphp
  backlog                 100
  instances               1
  priority                0
  memSoftLimit            2047M
  memHardLimit            2047M
  procSoftLimit           1400
  procHardLimit           1500
}

scripthandler  {
  add                     lsapi:lsphp php
}

railsDefaults  {
  maxConns                1
  env                     LSAPI_MAX_IDLE=60
  initTimeout             60
  retryTimeout            0
  pcKeepAliveTimeout      60
  respBuffer              0
  backlog                 50
  runOnStartUp            3
  extMaxIdleTime          300
  priority                3
  memSoftLimit            2047M
  memHardLimit            2047M
  procSoftLimit           500
  procHardLimit           600
}

wsgiDefaults  {
  maxConns                5
  env                     LSAPI_MAX_IDLE=60
  initTimeout             60
  retryTimeout            0
  pcKeepAliveTimeout      60
  respBuffer              0
  backlog                 50
  runOnStartUp            3
  extMaxIdleTime          300
  priority                3
  memSoftLimit            2047M
  memHardLimit            2047M
  procSoftLimit           500
  procHardLimit           600
}

nodeDefaults  {
  maxConns                5
  env                     LSAPI_MAX_IDLE=60
  initTimeout             60
  retryTimeout            0
  pcKeepAliveTimeout      60
  respBuffer              0
  backlog                 50
  runOnStartUp            3
  extMaxIdleTime          300
  priority                3
  memSoftLimit            2047M
  memHardLimit            2047M
  procSoftLimit           500
  procHardLimit           600
}

module cache {
internal            1
checkPrivateCache   1
checkPublicCache    1
maxCacheObjSize     10000000
maxStaleAge         200
qsCache             1
reqCookieCache      1
respCookieCache     1
ignoreReqCacheCtrl  1
ignoreRespCacheCtrl 0
enableCache         0
expireInSeconds     3600
enablePrivateCache  0
privateExpireInSeconds 3600
ls_enabled          1
}

listener HTTP {
  address                 *:80
  secure                  0
}

listener SSL {
  address                 *:443
  reusePort               1
  secure                  1
  keyFile                 /usr/local/lsws/conf/server.key
  certFile                /usr/local/lsws/conf/server.crt
  sslProtocol             24
  enableECDHE             0
  enableDHE               0
  renegProtection         1
  sslSessionCache         1
  sslSessionTickets       1
  enableQuic              1
}

EOL

# php settings
echoB "${FPACE} - Configuring PHP"
for inifile in $(find /usr/local/lsws/lsphp*/etc/php/ -type f -iname php.ini); do
echo "Editing $inifile ...";
cat >"${inifile}" <<EOL
[PHP]
max_input_vars = 10000
max_input_time = 90
output_buffering = 4096
short_open_tag = 1
engine = On
precision = 14
zlib.output_compression = Off
implicit_flush = Off
unserialize_callback_func =
serialize_precision = -1
disable_functions = exec,system,passthru,popen,shell_exec,pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,
disable_classes =
realpath_cache_size = 4096k
realpath_cache_ttl = 120
zend.enable_gc = On
expose_php = Off
max_execution_time = 300
memory_limit = 1024M
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 0
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On
html_errors = On
variables_order = "GPCS"
request_order = "GP"
register_argc_argv = Off
auto_globals_jit = On
post_max_size = 256M
auto_prepend_file =
auto_append_file =
default_mimetype = "text/html"
default_charset = "UTF-8"
doc_root =
user_dir =
enable_dl = Off
file_uploads = On
upload_max_filesize = 256M
max_file_uploads = 20
allow_url_fopen = On
allow_url_include = Off
default_socket_timeout = 60
open_basedir = 
[CLI Server]
cli_server.color = On
user_ini.filename = ".user.ini"
user_ini.cache_ttl = 60
[Date]
[filter]
[iconv]
[imap]
[intl]
[sqlite3]
[Pcre]
[Pdo]
[Pdo_mysql]
pdo_mysql.default_socket=
[Phar]
[mail function]
SMTP = localhost
smtp_port = 25
mail.add_x_header = Off
[ODBC]
odbc.allow_persistent = On
odbc.check_persistent = On
odbc.max_persistent = -1
odbc.max_links = -1
odbc.defaultlrl = 4096
odbc.defaultbinmode = 1
[Interbase]
ibase.allow_persistent = 1
ibase.max_persistent = -1
ibase.max_links = -1
ibase.timestampformat = "%Y-%m-%d %H:%M:%S"
ibase.dateformat = "%Y-%m-%d"
ibase.timeformat = "%H:%M:%S"
[MySQLi]
mysqli.max_persistent = -1
mysqli.allow_persistent = On
mysqli.max_links = -1
mysqli.default_port = 3306
mysqli.default_socket =
mysqli.default_host =
mysqli.default_user =
mysqli.default_pw =
mysqli.reconnect = Off
[mysqlnd]
mysqlnd.collect_statistics = On
mysqlnd.collect_memory_statistics = Off
[OCI8]
[PostgreSQL]
pgsql.allow_persistent = On
pgsql.auto_reset_persistent = Off
pgsql.max_persistent = -1
pgsql.max_links = -1
pgsql.ignore_notice = 0
pgsql.log_notice = 0
[bcmath]
bcmath.scale = 0
[browscap]
[Session]
session.save_handler = files
session.use_strict_mode = 0
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.auto_start = 0
session.cookie_lifetime = 0
session.cookie_path = /
session.cookie_domain =
session.cookie_httponly =
session.cookie_samesite =
session.serialize_handler = php
session.gc_probability = 0
session.gc_divisor = 1000
session.gc_maxlifetime = 1440
session.referer_check =
session.cache_limiter = nocache
session.cache_expire = 180
session.use_trans_sid = 0
session.sid_length = 26
session.trans_sid_tags = "a=href,area=href,frame=src,form="
session.sid_bits_per_character = 5
[Assertion]
zend.assertions = -1
[COM]
[mbstring]
[gd]
[exif]
[Tidy]
tidy.clean_output = Off
[soap]
soap.wsdl_cache_enabled=1
soap.wsdl_cache_dir="/tmp"
soap.wsdl_cache_ttl=86400
soap.wsdl_cache_limit = 5
[sysvshm]
[ldap]
ldap.max_links = -1
[dba]
[opcache]
opcache.enable=1
opcache.jit_buffer_size=1
opcache.jit_buffer_size=256M
opcache.memory_consumption=256
opcache.interned_strings_buffer=12
opcache.max_accelerated_files=128000
opcache.max_wasted_percentage=5
opcache.use_cwd=1
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.save_comments=1
opcache.max_file_size=1048576
opcache.force_restart_timeout=180
opcache.log_verbosity_level=1
[curl]
[openssl]
EOL

done


# php cli
# php settings
echoB "${FPACE} - Configuring PHP"
for inifile in $(find /etc/php/*/cli/ -type f -iname php.ini); do
echo "Editing $inifile ...";
cat >"${inifile}" <<EOL
[PHP]
max_input_vars = 10000
max_input_time = 3600
output_buffering = 4096
short_open_tag = On
engine = On
precision = 14
zlib.output_compression = Off
implicit_flush = Off
unserialize_callback_func =
serialize_precision = -1
disable_functions = 
disable_classes =
realpath_cache_size = 4096k
realpath_cache_ttl = 120
zend.enable_gc = On
expose_php = Off
max_execution_time = 3600
memory_limit = 4096M
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 0
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On
html_errors = On
variables_order = "GPCS"
request_order = "GP"
register_argc_argv = Off
auto_globals_jit = On
post_max_size = 384M
auto_prepend_file =
auto_append_file =
default_mimetype = "text/html"
default_charset = "UTF-8"
doc_root =
user_dir =
enable_dl = Off
file_uploads = On
upload_max_filesize = 256M
max_file_uploads = 10
allow_url_fopen = On
allow_url_include = Off
default_socket_timeout = 60
open_basedir = 
[CLI Server]
cli_server.color = On
user_ini.filename = ".user.ini"
user_ini.cache_ttl = 60
[Date]
[filter]
[iconv]
[imap]
[intl]
[sqlite3]
[Pcre]
[Pdo]
[Pdo_mysql]
pdo_mysql.default_socket=
[Phar]
[mail function]
SMTP = localhost
smtp_port = 25
mail.add_x_header = Off
[ODBC]
odbc.allow_persistent = On
odbc.check_persistent = On
odbc.max_persistent = -1
odbc.max_links = -1
odbc.defaultlrl = 4096
odbc.defaultbinmode = 1
[Interbase]
ibase.allow_persistent = 1
ibase.max_persistent = -1
ibase.max_links = -1
ibase.timestampformat = "%Y-%m-%d %H:%M:%S"
ibase.dateformat = "%Y-%m-%d"
ibase.timeformat = "%H:%M:%S"
[MySQLi]
mysqli.max_persistent = -1
mysqli.allow_persistent = On
mysqli.max_links = -1
mysqli.default_port = 3306
mysqli.default_socket =
mysqli.default_host =
mysqli.default_user =
mysqli.default_pw =
mysqli.reconnect = Off
[mysqlnd]
mysqlnd.collect_statistics = On
mysqlnd.collect_memory_statistics = Off
[OCI8]
[PostgreSQL]
pgsql.allow_persistent = On
pgsql.auto_reset_persistent = Off
pgsql.max_persistent = -1
pgsql.max_links = -1
pgsql.ignore_notice = 0
pgsql.log_notice = 0
[bcmath]
bcmath.scale = 0
[browscap]
[Session]
session.save_handler = files
session.use_strict_mode = 0
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.auto_start = 0
session.cookie_lifetime = 0
session.cookie_path = /
session.cookie_domain =
session.cookie_httponly =
session.cookie_samesite =
session.serialize_handler = php
session.gc_probability = 0
session.gc_divisor = 1000
session.gc_maxlifetime = 1440
session.referer_check =
session.cache_limiter = nocache
session.cache_expire = 180
session.use_trans_sid = 0
session.sid_length = 26
session.trans_sid_tags = "a=href,area=href,frame=src,form="
session.sid_bits_per_character = 5
[Assertion]
zend.assertions = -1
[COM]
[mbstring]
[gd]
[exif]
[Tidy]
tidy.clean_output = Off
[soap]
soap.wsdl_cache_enabled=1
soap.wsdl_cache_dir="/tmp"
soap.wsdl_cache_ttl=86400
soap.wsdl_cache_limit = 5
[sysvshm]
[ldap]
ldap.max_links = -1
[dba]
[opcache]
opcache.enable=0
opcache.jit_buffer_size=256M
opcache.memory_consumption=256
opcache.interned_strings_buffer=12
opcache.max_accelerated_files=128000
opcache.max_wasted_percentage=5
opcache.use_cwd=1
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.save_comments=1
opcache.max_file_size=1048576
opcache.force_restart_timeout=180
opcache.log_verbosity_level=1
[curl]
[openssl]

EOL

done

	sed -i '/adminEmails/c\adminEmails $EMAIL' "${WEBCF}"
	chown -R lsadm:lsadm $SERVER_ROOT/conf/
    else
        echoR "${WEBCF} is missing. It appears that something went wrong during OpenLiteSpeed installation."
        ALLERRORS=1
    fi
    echo custom > "$SERVER_ROOT/PLAT"
	sed -i s"|lsphp.*/bin/lsphp|lsphp${LSPHPVER}/bin/lsphp|g" ${WEBCF}
	killall -9 lsphp || echo "PHP process was not running."
	systemctl restart lshttpd
}

function check_cur_status
{
    if [ -e $SERVER_ROOT/bin/openlitespeed ] ; then
        OLSINSTALLED=1
    else
        OLSINSTALLED=0
    fi

    which mysqladmin  >/dev/null 2>&1
    if [ $? = 0 ] ; then
        MYSQLINSTALLED=1
    else
        MYSQLINSTALLED=0
    fi
}

function uninstall
{
    if [ "$OLSINSTALLED" = "1" ] ; then
        echoB "${FPACE} - Stop OpenLiteSpeed"
        silent $SERVER_ROOT/bin/lswsctrl stop
        echoB "${FPACE} - Stop LSPHP"
        silent killall -9 lsphp
        if [ "$OSNAME" = "centos" ] ; then
            uninstall_php_centos
            uninstall_ols_centos
        else
            uninstall_php_debian
            uninstall_ols_debian 
        fi
        echoG Uninstalled.
    else
        echoY "OpenLiteSpeed not installed."
    fi
}

function read_password
{
    if [ "$1" != "" ] ; then
        TEMPPASSWORD=$1
    else
        passwd=
        echoY "Please input password for $2(press enter to get a random one):"
        read passwd
        if [ "$passwd" = "" ] ; then
            TEMPPASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
        else
            TEMPPASSWORD=$passwd
        fi
    fi
}

function check_php_param
{
    if [ "$OSNAMEVER" = "UBUNTU22" ] || [ "$OSNAMEVER" = "UBUNTU20" ] || [ "$OSNAMEVER" = "UBUNTU18" ] || [ "$OSNAMEVER" = "DEBIAN9" ] || [ "$OSNAMEVER" = "DEBIAN10" ] || [ "$OSNAMEVER" = "DEBIAN11" ]; then
        if [ "$LSPHPVER" = "56" ]; then
            echoY "We do not support lsphp$LSPHPVER on $OSNAMEVER."
            LSPHPVER=74
        fi
    fi
}

function check_value_follow
{
    FOLLOWPARAM=$1
    local PARAM=$1
    local KEYWORD=$2

    if [ "$1" = "-n" ] || [ "$1" = "-e" ] || [ "$1" = "-E" ] ; then
        FOLLOWPARAM=
    else
        local PARAMCHAR=$(echo $1 | awk '{print substr($0,1,1)}')
        if [ "$PARAMCHAR" = "-" ] ; then
            FOLLOWPARAM=
        fi
    fi

    if [ -z "$FOLLOWPARAM" ] ; then
        if [ ! -z "$KEYWORD" ] ; then
            echoR "Error: '$PARAM' is not a valid '$KEYWORD', please check and try again."
            usage
        fi
    fi
}


function fixLangTypo
{
    WP_LOCALE="af ak sq am ar hy rup_MK as az az_TR ba eu bel bn_BD bs_BA bg_BG my_MM ca bal zh_CN \
      zh_HK zh_TW co hr cs_CZ da_DK dv nl_NL nl_BE en_US en_AU 	en_CA en_GB eo et fo fi fr_BE fr_FR \
      fy fuc gl_ES ka_GE de_DE de_CH el gn gu_IN haw_US haz he_IL hi_IN hu_HU is_IS ido id_ID ga it_IT \
      ja jv_ID kn kk km kin ky_KY ko_KR ckb lo lv li lin lt_LT lb_LU mk_MK mg_MG ms_MY ml_IN mr xmf mn \
      me_ME ne_NP nb_NO nn_NO ory os ps fa_IR fa_AF pl_PL pt_BR pt_PT pa_IN rhg ro_RO ru_RU ru_UA rue \
      sah sa_IN srd gd sr_RS sd_PK si_LK sk_SK sl_SI so_SO azb es_AR es_CL es_CO es_MX es_PE es_PR es_ES \
      es_VE su_ID sw sv_SE gsw tl tg tzm ta_IN ta_LK tt_RU te th bo tir tr_TR tuk ug_CN uk ur uz_UZ vi \
      wa cy yor"
    LANGSTR=$(echo "$WPLANGUAGE" | awk '{print tolower($0)}')
    if [ "$LANGSTR" = "zh_cn" ] || [ "$LANGSTR" = "zh-cn" ] || [ "$LANGSTR" = "cn" ] ; then
        WPLANGUAGE=zh_CN
    fi

    if [ "$LANGSTR" = "zh_tw" ] || [ "$LANGSTR" = "zh-tw" ] || [ "$LANGSTR" = "tw" ] ; then
        WPLANGUAGE=zh_TW
    fi
    echo ${WP_LOCALE} | grep -w "${WPLANGUAGE}" -q
    if [ ${?} != 0 ]; then 
        echoR "${WPLANGUAGE} language not found." 
        echo "Please check $WP_LOCALE"
        exit 1
    fi
}

function uninstall_warn
{
    if [ "$FORCEYES" != "1" ] ; then
        echo
        printf "\033[31mAre you sure you want to uninstall? Type 'Y' to continue, otherwise will quit.[y/N]\033[0m "
        read answer
        echo

        if [ "$answer" != "Y" ] && [ "$answer" != "y" ] ; then
            echoG "Uninstallation aborted!"
            exit 0
        fi
        echo 
    fi
    echoCYAN 'Start OpenLiteSpeed one click Uninstallation >> >> >> >> >> >> >>'
}

function befor_install_display
{
    echo
    echoCYAN "Starting to install OpenLiteSpeed to $SERVER_ROOT/ with the parameters below,"
	echoY "WebAdmin URL:             " "https://$SERVERIP:7080"
	echoY "WebAdmin user:            " "admin"
    echoY "WebAdmin pass:            " "$ADMINPASSWORD"
    echoY "WebAdmin email:           " "$EMAIL"
    echoY "LSPHP version:            " "$LSPHPVER"
    echoY "MariaDB version:          " "$MARIADBVER"
	echoY "MariaDB admin user:       " "root"
	echoY "MariaDB admin pass:       " "$ROOTPASSWORD"
    echoY "Server HTTP port:         " "$WPPORT"
    echoY "Server HTTPS port:        " "$SSLWPPORT"

    echoNW "Your password will be written to file:  ${PWD_FILE}"
    echo 
    if [ "$FORCEYES" != "1" ] ; then
        printf 'Are these settings correct? Type n to quit, otherwise will continue. [Y/n]'
        read answer
        if [ "$answer" = "N" ] || [ "$answer" = "n" ] ; then
            echoG "Aborting installation!"
            exit 0
        fi
    fi  
    echo
    echoCYAN 'Starting Setup ...'
}

function install_wp_cli
{
    if [ -e /usr/local/bin/wp ] || [ -e /usr/bin/wp ]; then 
        echoG 'WP CLI already exist'
    else    
        echoG "Install wp_cli"
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        echo $PATH | grep '/usr/local/bin' >/dev/null 2>&1
        if [ ${?} = 0 ]; then
            mv wp-cli.phar /usr/local/bin/wp
        else
            mv wp-cli.phar /usr/bin/wp
        fi    
    fi
    if [ ! -e /usr/bin/php ] && [ ! -L /usr/bin/php ]; then
        ln -s ${SERVER_ROOT}/lsphp${LSPHPVER}/bin/php /usr/bin/php
    elif [ ! -e /usr/bin/php ]; then 
        rm -f /usr/bin/php
        ln -s ${SERVER_ROOT}/lsphp${LSPHPVER}/bin/php /usr/bin/php    
    else 
        echoG '/usr/bin/php symlink exist, skip symlink.'    
    fi
}

function main_pure_db
{
    echoG 'Install MariaDB'
    pure_mariadb
}

function check_port_usage
{
    if [ "$WPPORT" = "80" ] || [ "$SSLWPPORT" = "443" ]; then
        echoG "Avoid port 80/443 conflict."
        killall -9 apache  >/dev/null 2>&1
        killall -9 apache2  >/dev/null 2>&1
        killall -9 httpd    >/dev/null 2>&1
        killall -9 nginx    >/dev/null 2>&1
    fi
}

function after_install_display
{
    chmod 600 "${PWD_FILE}"
    if [ "$ALLERRORS" = "0" ] ; then
        echoG "Congratulations! Installation finished."
    else
        echoY "Installation finished. Some errors seem to have occurred, please check this as you may need to manually fix them."
    fi
    echoCYAN 'End OpenLiteSpeed one click installation!'
    echo
}

function test_page
{
    local URL=$1
    local KEYWORD=$2
    local PAGENAME=$3
    curl -skL  $URL | grep -i "$KEYWORD" >/dev/null 2>&1
    if [ $? != 0 ] ; then
        echoR "Error: $PAGENAME failed."
        TESTGETERROR=yes
    else
        echoG "OK: $PAGENAME passed."
    fi
}

function test_ols_admin
{
    test_page https://localhost:7080/ "LiteSpeed WebAdmin" "test webAdmin page"
}

function main_ols_test
{
    echoCYAN "Starting auto testing..."
    test_ols_admin

    if [ "${TESTGETERROR}" = "yes" ] ; then
        echoG "Errors were encountered during testing. In many cases these errors can be solved manually by referring to installation logs."
        echoG "Service loading issues can sometimes be resolved by performing a restart of the web server."
        echoG "Reinstalling the web server can also help if neither of the above approaches resolve the issue."
    fi

    echoCYAN "Ended auto testing."
    echoG 'Thanks for using OpenLiteSpeed!'
    echo
}

function main_init_check
{
    check_root
    check_os
    check_cur_status
    check_php_param
}

function main_init_package
{
    update_centos_hashlib
    update_system
    check_wget
    check_curl
	check_firewall
	check_server
	check_packages
}

function main
{
    display_license
    main_init_check
    action_uninstall
    action_purgeall
    update_email
    main_gen_password
    befor_install_display
    main_init_package
    install_openlitespeed
    main_ols_password
    gen_selfsigned_cert
    main_pure_db
    config_server
    restart_lsws
    after_install_display
    main_ols_test
}

while [ ! -z "${1}" ] ; do
    case "${1}" in
        -[aA] | --adminpassword )  
                check_value_follow "$2" ""
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                ADMINPASSWORD=$FOLLOWPARAM
                ;;
        -[eE] | --email )          
                check_value_follow "$2" "email address"
                shift
                EMAIL=$FOLLOWPARAM
                ;;
        --lsphp )           
                check_value_follow "$2" "LSPHP version"
                shift
                cnt=${#LSPHPVERLIST[@]}
                for (( i = 0 ; i < cnt ; i++ )); do
                    if [ "$1" = "${LSPHPVERLIST[$i]}" ] ; then LSPHPVER=$1; fi
                done
                ;;
        --mariadbver )      
                check_value_follow "$2" "MariaDB version"
                shift
                cnt=${#MARIADBVERLIST[@]}
                for (( i = 0 ; i < cnt ; i++ )); do 
                    if [ "$1" = "${MARIADBVERLIST[$i]}" ] ; then MARIADBVER=$1; fi 
                done
                ;;
        -[rR] | --dbrootpassword ) 
                check_value_follow "$2" ""
                if [ ! -z "$FOLLOWPARAM" ] ; then shift; fi
                ROOTPASSWORD=$FOLLOWPARAM
                ;;
        --listenport )      
                check_value_follow "$2" "HTTP listen port"
                shift
                WPPORT=$FOLLOWPARAM
                ;;
        --ssllistenport )   
                check_value_follow "$2" "HTTPS listen port"
                shift
                SSLWPPORT=$FOLLOWPARAM
                ;;               
        -[Uu] | --uninstall )       
                ACTION=UNINSTALL
                ;;
        -[Pp] | --purgeall )        
                ACTION=PURGEALL
                ;;
        -[qQ] | --quiet )           
                FORCEYES=1
                ;;
        -V | --version )     
                display_license
                exit 0
                ;;
        -v | --verbose )             
                VERBOSE=1
                APT='apt-get'
                YUM='yum'
                ;;
        -[hH] | --help )           
                usage
                ;;
        * )                     
                usage
                ;;
    esac
    shift
done

main

