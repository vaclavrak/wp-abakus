#!/bin/bash
# WordPress LEMP Stack Installation Script
# Ubuntu 24.04 LTS + nginx + PHP 8.3 + MariaDB

set -e
exec > >(tee /var/log/startup-script.log) 2>&1

echo "=== Starting LEMP Stack Installation ==="
echo "Date: $(date)"

# Get domain from metadata
DOMAIN=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/domain" -H "Metadata-Flavor: Google" || echo "localhost")
echo "Domain: $DOMAIN"

# Update system
echo "=== Updating system ==="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install nginx
echo "=== Installing nginx ==="
apt-get install -y nginx

# Install PHP 8.3 and extensions
echo "=== Installing PHP 8.3 ==="
apt-get install -y php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-intl \
    php8.3-mbstring php8.3-soap php8.3-xml php8.3-xmlrpc php8.3-zip php8.3-imagick php8.3-cli

# Install MariaDB
echo "=== Installing MariaDB ==="
apt-get install -y mariadb-server mariadb-client

# Start and enable services
systemctl start mariadb
systemctl enable mariadb
systemctl start php8.3-fpm
systemctl enable php8.3-fpm
systemctl start nginx
systemctl enable nginx

# Secure MariaDB (non-interactive)
echo "=== Securing MariaDB ==="
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '';"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

# Create WordPress database and user
echo "=== Creating WordPress database ==="
WP_DB_PASSWORD=$(openssl rand -base64 24)
mysql -e "CREATE DATABASE IF NOT EXISTS wordpress DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'wordpress'@'localhost' IDENTIFIED BY '${WP_DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Save credentials
echo "WP_DB_PASSWORD=${WP_DB_PASSWORD}" > /root/.wp-credentials
chmod 600 /root/.wp-credentials
echo "Database credentials saved to /root/.wp-credentials"

# Configure PHP
echo "=== Configuring PHP ==="
cat > /etc/php/8.3/fpm/conf.d/99-wordpress.ini << 'EOF'
upload_max_filesize = 64M
post_max_size = 64M
memory_limit = 256M
max_execution_time = 300
max_input_vars = 3000
EOF

# Configure PHP-FPM pool
sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.3/fpm/php.ini

# Create WordPress directory
echo "=== Setting up WordPress directory ==="
mkdir -p /var/www/wordpress
chown -R www-data:www-data /var/www/wordpress

# Configure nginx for WordPress
echo "=== Configuring nginx ==="
cat > /etc/nginx/sites-available/wordpress << EOF
# Redirect www to non-www (HTTPS)
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    # Let's Encrypt challenge
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/wordpress;
    }

    # Redirect all HTTP to HTTPS (main domain)
    location / {
        return 301 https://${DOMAIN}\$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    root /var/www/wordpress;
    index index.php index.html;

    # Redirect www to non-www
    if (\$host = www.${DOMAIN}) {
        return 301 https://${DOMAIN}\$request_uri;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    access_log /var/log/nginx/wordpress.access.log;
    error_log /var/log/nginx/wordpress.error.log;

    # Max upload size
    client_max_body_size 64M;

    # Include security snippets (created later in script)
    include /etc/nginx/snippets/security-xmlrpc.conf;
    include /etc/nginx/snippets/health-check.conf;
    # include /etc/nginx/snippets/hide-my-wp.conf;  # Enable after WordPress migration

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP handling
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }

    location ~* /(?:uploads|files)/.*\.php\$ {
        deny all;
    }

    # Static file caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # SSL placeholder - certbot will update this
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
}
EOF

# Enable WordPress site
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/

# Test and reload nginx
nginx -t
systemctl reload nginx

# Install certbot for Let's Encrypt
echo "=== Installing Certbot ==="
apt-get install -y certbot python3-certbot-nginx

# Install additional tools
echo "=== Installing additional tools ==="
apt-get install -y unzip curl wget htop

# Create migration helper script location
mkdir -p /root/scripts

# Create simple status page
cat > /var/www/wordpress/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>WordPress Server Ready</title></head>
<body>
<h1>LEMP Stack Ready</h1>
<p>Server is configured and waiting for WordPress migration.</p>
<ul>
<li>nginx: running</li>
<li>PHP 8.3-FPM: running</li>
<li>MariaDB: running</li>
</ul>
<p>Domain: ${DOMAIN}</p>
<p>Run the migration script to complete WordPress setup.</p>
</body>
</html>
EOF

# ===========================================
# SECURITY HARDENING
# ===========================================

echo "=== Installing Security Tools ==="
DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban unattended-upgrades apt-listchanges

# Configure fail2ban
echo "=== Configuring fail2ban ==="
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h

[wordpress]
enabled = true
port = http,https
filter = wordpress
logpath = /var/log/nginx/wordpress.access.log
maxretry = 5
findtime = 5m
bantime = 1h
EOF

cat > /etc/fail2ban/filter.d/wordpress.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST .*(wp-login\.php|prihlaseni).* HTTP/.*" (200|403) .*$
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Configure unattended-upgrades
echo "=== Configuring automatic security updates ==="
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades

# Harden SSH - key-only authentication
echo "=== Hardening SSH ==="
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config
systemctl restart ssh

# Create nginx security snippets
echo "=== Creating nginx security snippets ==="

# XML-RPC block
cat > /etc/nginx/snippets/security-xmlrpc.conf << 'EOF'
location = /xmlrpc.php {
    deny all;
    access_log off;
    log_not_found off;
    return 444;
}
EOF

# Health check endpoint for monitoring
cat > /etc/nginx/snippets/health-check.conf << 'EOF'
location = /health {
    access_log off;
    add_header Content-Type text/plain;
    return 200 "OK";
}
EOF

# Hide My WP rules (applied after WordPress migration)
cat > /etc/nginx/snippets/hide-my-wp.conf << 'EOF'
# BEGIN Hide My WP
if ($args !~ "ca_pristup=skryt"){
    set $rule_0 1;
}
if ($http_cookie !~* "eadcc=1"){
    set $rule_0 "${rule_0}2";
}
if ($rule_0 = "12"){
    rewrite ^/((wp-content|wp-includes|wp-admin)/(.*)) /nothing_404_404?ca_pristup=skryt last;
}
rewrite ^/prihlaseni /wp-login.php?ca_pristup=skryt last;
rewrite ^/lib/(.*) /wp-includes/$1?ca_pristup=skryt last;
rewrite ^/file/(.*) /wp-content/uploads/$1?ca_pristup=skryt last;
rewrite ^/ext/(.*) /wp-content/plugins/$1?ca_pristup=skryt last;
rewrite ^/skin/(.*) /wp-content/themes/hello-theme-child-master/$1?ca_pristup=skryt last;
rewrite ^/ajax /wp-admin/admin-ajax.php?ca_pristup=skryt last;
rewrite ^/inc/(.*) /wp-content/$1?ca_pristup=skryt last;
# END Hide My WP
EOF

echo "=== LEMP Stack Installation Complete ==="
echo "Database credentials: /root/.wp-credentials"
echo "Security: fail2ban, unattended-upgrades, SSH key-only"
echo "Next step: Run migrate-wordpress.sh to import WordPress"
