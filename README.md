# Open LiteSpeed + PerconaDB setup

This repository contains a shell script compatible with Ubuntu 22.04 for setting up an Open LiteSpeed web server with PerconaDB and PHP FPM. It performs a variety of server setup tasks, installs the necessary packages, and generates a self-signed SSL certificate for the server.

## How to run

To run the script, you can use the following command:

```curl -s https://raw.githubusercontent.com/peixotorms/ols/main/ols.sh | bash```


## What it does

The shell script performs various functions such as calculating memory configurations for your server size, updating the system, setting up repositories, reconfiguring the firewall, installing OpenLiteSpeed, LetsEncrypt, PHP-FPM (7.4,8.0,8.1,8.2) with OPCACHE, WP-CLI, Percona Server 8.0 for MySQL, Postfix and Redis.

## License

The script is licensed under the MIT License.
