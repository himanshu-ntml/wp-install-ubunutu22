# **PHP-FPM optimization** (memory limits, max children, etc.)
echo "▶ Configuring PHP-FPM for optimal performance"
cat >> /etc/php/8.1/fpm/pool.d/www.conf <<EOF
pm.max_children = 512
pm.start_servers = 64
pm.min_spare_servers = 32
pm.max_spare_servers = 128
pm.max_requests = 500
EOF

# Restart PHP-FPM
echo "▶ Restarting PHP-FPM"
service php8.1-fpm restart

# **Log Rotation for Nginx Logs**
echo "▶ Installing and configuring log rotation for Nginx"
apt-get install -y logrotate

# Create a logrotate configuration for Nginx logs
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

echo "Log rotation configuration completed."

# **Fail2Ban for Security**
echo "▶ Installing Fail2Ban to protect against brute-force attacks"
apt-get install -y fail2ban

# Enable and start fail2ban
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

echo "Fail2Ban configuration completed."

# **SSL Automatic Renewal (optional)**
echo "▶ Enabling automatic Let's Encrypt SSL renewal"
echo "0 0 * * * certbot renew --quiet && systemctl reload nginx" | tee -a /etc/crontab

# Restart Nginx to apply the changes
systemctl reload nginx

# Clean up temporary files
echo "▶ Cleaning up temporary files"
rm -rf /tmp/*

echo "WordPress installation, Nginx, PHP optimization, backup, and security setup completed successfully!"
