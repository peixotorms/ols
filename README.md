# Open LiteSpeed + PerconaDB setup

This repository contains a shell script for setting up an Open LiteSpeed web server with PerconaDB on Ubuntu 20.04. It performs a variety of server setup tasks, installs the necessary packages, and generates a self-signed SSL certificate for the server.

## How to run

To run the script, you can use the following command:

```curl -s https://raw.githubusercontent.com/peixotorms/ols/main/ols.sh | bash```


## Functions

The shell script contains the following functions:

* `calculate_memory_configs`: calculates memory configurations for various components based on the available system memory and CPU cores.
* `update_system`: updates the system and disables hints on pending kernel upgrades.
* `setup_repositories`: sets up the necessary repositories for Percona, OpenLiteSpeed, and PHP.
* `setup_firewall`: sets up and configures the firewall using ufw (Uncomplicated Firewall).
* `setup_basic`: performs a variety of basic server setup tasks, including reconfiguring timezone and locale settings, setting the default text editor to nano, adding 'localhost' entry to /etc/hosts if it doesn't exist, updating /etc/security/limits.conf with nofile limits, creating or resizing the swapfile to a permanent 2GB size, and ensuring idempotency for /etc/security/limits.conf and /etc/fstab by removing comments and empty lines.
* `setup_packages`: installs a variety of necessary packages for the server, including basic packages, OpenLiteSpeed web server and its PHP 8.0 packages, PHP FPM and its extensions for different PHP versions (7.4, 8.0, 8.1, and 8.2), WP-CLI, a command-line tool for managing WordPress installations, Postfix, an open-source mail transfer agent (MTA) for routing and delivering email, and Percona Server, a high-performance alternative to MySQL, for database management.
* `setup_selfsigned_cert`: generates and installs a self-signed SSL certificate for the server. The generated certificate is valid for 820 days and is made for OpenLiteSpeed.

## Credits

The script was created by Raul Peixoto from WP Raiser and is based on the LiteSpeed 1-Click Install OLS.

## License

The script is licensed under the MIT License.
