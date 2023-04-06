# OpenLiteSpeed, LetsEncrypt, PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI, Percona Server 8.0 for MySQL, Postfix and Redis

This repository contains a shell script compatible with Ubuntu 22.04 for setting up a high performance web server.

## How to install

To run the script, you can use the following command:

```curl -k -s https://raw.githubusercontent.com/peixotorms/ols/main/ols.sh | bash```

Or run with options:

```bash <( curl -k -s https://raw.githubusercontent.com/peixotorms/ols/main/ols.sh ) -h```

## Usage

The script accepts the following options:

```
--functions, -f
    Run a comma-separated list of function names. 
    Default: update_system, setup_sshd, setup_repositories, setup_firewall, install_basic_packages, install_ols, install_php, install_wp_cli, install_percona, install_redis, install_postfix

--user, -u
    Customize OpenLiteSpeed username. Default: admin.

--pass, -p
    Customize OpenLiteSpeed password. Default: empty.

--verbose, -v
    Enable verbose mode.

--help, -h
    Show usage instructions and exit.

```

## What it does

The shell script performs various functions such as calculating memory configurations for your server size, updating the system, setting up repositories, reconfiguring the firewall, installing OpenLiteSpeed, LetsEncrypt, PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI, Percona Server 8.0 for MySQL, Postfix and Redis.

## License

The script is licensed under the MIT License.
