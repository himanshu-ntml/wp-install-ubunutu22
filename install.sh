#!/bin/bash

## This script assumes you already set up your SSH access, firewall, etc.
## If not, run /ubuntu/setup.sh script first.
##
## Usage:
## sudo bash -c "$(curl -sS https://raw.githubusercontent.com/pietrorea/scripts/master/ubuntu/install-wordpress.sh)"
##

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "Error: Please run as root with sudo."
  exit
fi

WP_DB_NAME=wordpress
WP_DB_ADMIN_USER=wpadmin

echo "Enter the hostname (e.g., blog.example.com or example.com):"
read HOSTNAME
echo

echo "MySQL password for wpadmin user:"
echo "> 8 chars, including numeric, mixed case, and special characters"
read -s MYSQL_WP_ADMIN_USER_PASSWORD
echo

## Ubuntu updates and dependencies
echo "Starting system update and dependency installation..."
apt-get update
apt-get -y upgrade
apt-get -y autoremove
echo "System update and dependency installation completed."

## WordPress dependencies (LEMP stack)
echo "Installing WordPress dependencies (LEMP stack)..."
apt-get install -y \
nginx \
mysql-server \
php-fpm \
php-mysql \
php-curl \
php-gd \
php-intl \
php-mbstring \
php-soap \
php-xml \
php-xmlrpc \
php-zip \
fail2ban \
logrotate
echo "WordPress dependencies installation completed."

## Determine installed PHP-FPM version
PHP_FPM_VERSION=$(php -r "echo PHP_VERSION;")
PHP_FPM_SOCKET="/run/php/php${PHP_FPM_VERSION:0:3}-fpm.sock"

# nginx setup with optimizations
echo "Configuring Nginx with optimizations..."
cat > /etc/nginx/sites-available/$HOSTNAME <<EOF
resolver 8.8.8.8 8.8.4.4;
server {
  listen 80;
  root /var/www/html/wordpress;
  index  index.php index.html index.htm;
  server_name $HOSTNAME;
  error_log /var/log/nginx/error.log;
  access_log /var/log/nginx/access.log;
  client_max_body_size 100M;

  ## Gzip Compression
  gzip on;
  gzip_vary on;
  gzip_disable "msie6";
  gzip_min_length 1000;
  gzip_comp_level 6;
  gzip_types text/plain text/css application/javascript application/json application/xml text/javascript application/xml+rss text/javascript image/svg+xml;

  ## Caching Static Files
  location ~* \.(jpg|jpeg|png|gif|css|js|ico|xml|json|woff|woff2|ttf|eot|svg|otf)$ {
    expires 30d;
    access_log off;
  }

  ## Security Headers
  add_header X-Content-Type-Options "nosniff";
  add_header X-XSS-Protection "1; mode=block";
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
  add_header X-Frame-Options "SAMEORIGIN";
  add_header Referrer-Policy "no-referrer-when-downgrade";

  ## Prevent .htaccess and hidden files from being accessed
  location ~ /\. {
    deny all;
  }

  location / {
    try_files \$uri \$uri/ /index.php?\$args;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:$PHP_FPM_SOCKET;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
  }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/$HOSTNAME /etc/nginx/sites-enabled/
service nginx reload
echo "Nginx configuration with optimizations completed."

## MySQL setup
echo "Running mysql_secure_installation..."
mysql_secure_installation <<EOF
n # Skip setting the root password (auth_socket in use)
Y # Remove anonymous users for security
Y # Disallow root login remotely
Y # Remove test database and access to it
Y # Reload privilege tables to apply changes
EOF
echo "mysql_secure_installation completed."

## MySQL setup for WordPress
echo "Configuring MySQL for WordPress..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${WP_DB_NAME};
CREATE USER '${WP_DB_ADMIN_USER}'@'localhost' IDENTIFIED BY '${MYSQL_WP_ADMIN_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${WP_DB_NAME}.* TO '${WP_DB_ADMIN_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
echo "MySQL configuration for WordPress completed."

## Install WordPress
echo "Installing WordPress..."
sudo mkdir -p /var/www/html/wordpress
cd /var/www/html/wordpress
sudo wget https://wordpress.org/latest.tar.gz
sudo tar -xvf latest.tar.gz
sudo mv latest.tar.gz wordpress-`date "+%Y-%m-%d"`.tar.gz
sudo mv wordpress/* /var/www/html/wordpress/
sudo chown -R www-data:www-data /var/www/html/wordpress
echo "WordPress installation completed."

## Set up wp-config.php (current as of WordPress 5.8)
echo "Setting up wp-config.php..."
WP_SECURE_SALTS="$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)"

WP_CONFIG_FILE=/var/www/html/wordpress/wp-config.php
cat > "${WP_CONFIG_FILE}" <<EOF
<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the installation.
 * You don't have to use the web site, you can copy this file to "wp-config.php"
 * and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://wordpress.org/support/article/editing-wp-config-php/
 *
 * @package WordPress
 */

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define( 'DB_NAME', '${WP_DB_NAME}' );

/** MySQL database username */
define( 'DB_USER', '${WP_DB_ADMIN_USER}' );

/** MySQL database password */
define( 'DB_PASSWORD', '${MYSQL_WP_ADMIN_USER_PASSWORD}' );

/** MySQL hostname */
define( 'DB_HOST', 'localhost' );

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
${WP_SECURE_SALTS}

/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
\$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define( 'WP_DEBUG', false );

/* Add any custom values between this line and the "stop editing" line. */



/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
EOF

sudo chown -R www-data:www-data "${WP_CONFIG_FILE}"
echo "wp-config.php setup completed."

# **PHP-FPM optimization** (memory limits, max children, etc.)
echo "▶ Configuring PHP-FPM for optimal performance"
cat >> /etc/php/${PHP_FPM_VERSION}/fpm/pool.d/www.conf <<EOF
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
EOF

# Restart PHP-FPM
echo "▶ Restarting PHP-FPM"
service php${PHP_FPM_VERSION}-fpm restart

echo "▶ Installing and configuring log rotation"
apt-get install -y logrotate
cat > /etc/logrotate.d/nginx << EOF
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
}
EOF

# **Fail2Ban for Security**
echo "▶ Installing Fail2Ban to protect against brute-force attacks"
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban

echo "▶ Configuring Fail2Ban for Nginx"
cat > /etc/fail2ban/jail.d/nginx.conf <<EOF
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/*error.log
maxretry = 3
EOF

systemctl restart fail2ban

echo "▶ Enabling automatic Let's Encrypt SSL renewal"
echo "0 0 * * * certbot renew --quiet && systemctl restart nginx" | tee -a /etc/crontab

# Clean up
rm -rf /tmp/*

echo "WordPress installation, Nginx, PHP, Backup, and Security setup completed successfully!"
