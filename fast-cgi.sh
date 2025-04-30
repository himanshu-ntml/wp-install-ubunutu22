#!/bin/bash

# Check if Nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "Nginx is not installed. Please install Nginx first."
    exit 1
fi

# Check if PHP-FPM is installed
if ! command -v php-fpm &> /dev/null; then
    # Check if PHP-FPM service exists with version
    if ! systemctl list-units | grep -q 'php.*-fpm'; then
        echo "PHP-FPM is not installed. Please install PHP-FPM first."
        exit 1
    fi
fi

# Nginx cache directory
CACHE_DIR="/var/cache/nginx/fastcgi_cache"

# PHP-FPM version (Assuming PHP 8.1, adjust if necessary)
PHP_FPM_VERSION="8.1"
PHP_FPM_SOCKET="/var/run/php/php${PHP_FPM_VERSION}-fpm.sock"

# Nginx configuration directory
NGINX_CONF_DIR="/etc/nginx"
SITE_CONFIG_DIR="/etc/nginx/sites-available"
SITE_CONFIG_FILE="$SITE_CONFIG_DIR/nginx.convivity.com"

# Check if the site configuration file exists
if [ ! -f "$SITE_CONFIG_FILE" ]; then
    echo "Site configuration file $SITE_CONFIG_FILE does not exist. Please create the site configuration first."
    exit 1
fi

# Backup the original configuration file before modifying
cp $SITE_CONFIG_FILE $SITE_CONFIG_FILE.bak

# Append FastCGI Cache Configuration to the existing site config
echo "Appending FastCGI cache configuration to $SITE_CONFIG_FILE..."

cat >> "$SITE_CONFIG_FILE" <<EOF

# FastCGI cache configuration for WordPress
set \$skip_cache 0;
if (\$http_cookie ~* "wordpress_logged_in_") {
    set \$skip_cache 1;
}

fastcgi_cache_bypass \$skip_cache;
fastcgi_no_cache \$skip_cache;

fastcgi_cache wordpress_cache;
fastcgi_cache_valid 200 302 1h;
fastcgi_cache_valid 404 1m;
fastcgi_cache_revalidate on;
fastcgi_cache_background_update on;
fastcgi_cache_lock on;
fastcgi_cache_use_stale error timeout http_500 http_502 http_503 http_504;

# PHP processing for this server
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:$PHP_FPM_SOCKET;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
}

location / {
    try_files \$uri \$uri/ /index.php?\$args;
}
EOF

# Create the FastCGI cache directory if it doesn't exist
mkdir -p $CACHE_DIR
chown -R www-data:www-data $CACHE_DIR

# Test Nginx configuration for errors
echo "Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "Nginx configuration is valid. Restarting Nginx..."
    # Restart Nginx to apply changes
    systemctl restart nginx
    echo "FastCGI caching has been implemented for $SITE_CONFIG_FILE, and Nginx has been restarted."
else
    echo "Nginx configuration is invalid. Please check the error above and fix it."
    exit 1
fi
