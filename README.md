# OpenLiteSpeed, LetsEncrypt, PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI, Percona Server 8.0 for MySQL, Postfix and Redis

This repository contains a shell script compatible with Ubuntu 22.04 for setting up a high performance web server.
The shell script performs various functions such as calculating memory configurations for your server size, updating the system, setting up repositories, reconfiguring the firewall, installing OpenLiteSpeed, LetsEncrypt, PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI, Percona Server 8.0 for MySQL, Postfix and Redis.

## How to install

To run the script, you can use the following command:

```bash <( curl -k -s https://raw.githubusercontent.com/peixotorms/ols/main/server.sh ) -h```

## Install Usage

The script accepts the following options:

```
--functions, -f
    Run a comma-separated list of function names. 
    Default: update_system, update_limits, setup_sshd, setup_repositories, setup_firewall, install_basic_packages, install_ols, install_php, install_wp_cli, install_percona, install_redis, install_postfix

--ols_user (optional)       Customize OpenLiteSpeed username. Must be between 8-32 alphanumeric chars.
--ols_pass (optional)       Customize OpenLiteSpeed password. Must be between 8-32 alphanumeric chars include at least one of the following symbols: ,+=-_!@
--ols_port (optional)       Customize OpenLiteSpeed port.
--verbose, -v (optional)    Enable verbose mode.
--help, -h                  Show this help message

```

## Examples:
```
bash server.sh --help
bash server.sh --verbose --functions "update_system,setup_repositories,setup_firewall,install_wp_cli"
bash server.sh --ols_user "myusername" --ols_pass "mypassword"
```


## Virtual Hosts

To add a domain, you can use the following command:

```bash <( curl -k -s https://raw.githubusercontent.com/peixotorms/ols/main/vhost.sh ) -h```

## Vitual Hosts Usage

The script accepts the following options:

```
--domain (required)         Domain name to set up
--aliases (optional)        Comma-separated list of domain aliases
--ssl (optional)            Enable or disable SSL. Default is 'yes'
--php (optional)            PHP version to install. Must be 7.4, 8.0, 8.1, or 8.2. Default is '8.0'
--vpath (optional)          Path to install website. Default is '/home/sites/<domain_name>'
--sftp_user (optional)      SFTP username. Default is generated from domain name
--sftp_pass (optional)      SFTP password. Default is a random 32 char pass
--db_host (optional)        Database host. Default is 'localhost'
--db_port (optional)        Database port. Default is '3306'
--db_user (optional)        Database username. Default is generated from domain name
--db_pass (optional)        Database password. Default is a random 32 char pass
--wp_install (optional)     Install WordPress or not. Default is 'yes'
--wp_user (optional)        WordPress username. Default is generated from domain name
--wp_pass (optional)        WordPress password. Default is a random 32 char pass
--dev_mode (optional)       Enable or disable developer mode. Default is 'no'
--help, -h                  Show this help message

```

## Examples:
```
bash vhost.sh --help
bash vhost.sh --domain example.com
bash vhost.sh --domain example.com --ssl no --php 7.4 --wp_install no
bash vhost.sh --domain "example.com" --aliases "example.net,example.org"
```

## License

The script is licensed under the MIT License.
