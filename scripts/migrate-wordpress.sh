#!/bin/bash
# WordPress Migration Script
# Run this on the VM after uploading database.sql and wp-content.tar.gz

set -e

echo "=== WordPress Migration Script ==="
echo "Date: $(date)"

# Configuration
WP_DIR="/var/www/wordpress"
UPLOAD_DIR="/tmp/wp-migration"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Check for required files
if [ ! -f "${UPLOAD_DIR}/database.sql" ]; then
    echo "ERROR: ${UPLOAD_DIR}/database.sql not found"
    echo "Upload it first: gcloud compute scp database.sql VM_NAME:/tmp/wp-migration/"
    exit 1
fi

if [ ! -f "${UPLOAD_DIR}/wp-content.tar.gz" ]; then
    echo "ERROR: ${UPLOAD_DIR}/wp-content.tar.gz not found"
    echo "Upload it first: gcloud compute scp wp-content.tar.gz VM_NAME:/tmp/wp-migration/"
    exit 1
fi

# Load database credentials
if [ ! -f /root/.wp-credentials ]; then
    echo "ERROR: /root/.wp-credentials not found. Run startup.sh first."
    exit 1
fi
source /root/.wp-credentials

# Get domain from metadata
DOMAIN=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/domain" -H "Metadata-Flavor: Google" || echo "localhost")
echo "Domain: $DOMAIN"

# Download WordPress
echo "=== Downloading WordPress ==="
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* ${WP_DIR}/
rm -rf wordpress latest.tar.gz

# Extract wp-content
echo "=== Extracting wp-content ==="
cd ${UPLOAD_DIR}
tar -xzf wp-content.tar.gz
cp -r wp-content/* ${WP_DIR}/wp-content/

# Import database
echo "=== Importing database ==="
# The database dump uses 'bitnami_wordpress', we need to import it to 'wordpress'
# First, replace the database name if needed
sed -i 's/bitnami_wordpress/wordpress/g' ${UPLOAD_DIR}/database.sql
mysql wordpress < ${UPLOAD_DIR}/database.sql
echo "Database imported successfully"

# Update URLs in database to new domain
echo "=== Updating URLs in database ==="
mysql wordpress << EOF
UPDATE wp_options SET option_value = 'https://${DOMAIN}' WHERE option_name = 'siteurl';
UPDATE wp_options SET option_value = 'https://${DOMAIN}' WHERE option_name = 'home';
EOF

# Create wp-config.php with original salts
echo "=== Creating wp-config.php ==="
cat > ${WP_DIR}/wp-config.php << EOF
<?php
define('DB_NAME', 'wordpress');
define('DB_USER', 'wordpress');
define('DB_PASSWORD', '${WP_DB_PASSWORD}');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

// Original salts from old site (preserves user sessions)
define('AUTH_KEY',         '476f0dbcc0203b85b861129a5130793725700d7797752b84015c27d6620e98fb');
define('SECURE_AUTH_KEY',  '78633031d1694da897ffa2c7375082c1d5a48f448e030e87bdd6b26a97d6c49e');
define('LOGGED_IN_KEY',    'f9c4f7110ef49718255021f409ae8859df8dfd79554e270970b655345fec5855');
define('NONCE_KEY',        '9893fe65bd201817c70ef3d6137512656501b51ad308c81bf1249595acb75df4');
define('AUTH_SALT',        '7307fe64bd69e68083245f0ec946b726bb3786698803e6382ca296512e95a0ce');
define('SECURE_AUTH_SALT', '749eadc46c4992427ebb060eeca93c4f463c1442af59ac9b26dd92a5ac7e7a86');
define('LOGGED_IN_SALT',   '9c875406eb98b098591ba4a21c3ba962b2200f09611a7eb7f258e060e191f229');
define('NONCE_SALT',       '350ca2e8286022818df05b8987005bd24387bfbdaca5a7afd1a423391cfed20b');

\$table_prefix = 'wp_';

define('WP_DEBUG', false);
define('FS_METHOD', 'direct');
define('DISALLOW_FILE_EDIT', true);

// Force HTTPS
define('FORCE_SSL_ADMIN', true);
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
}

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF

# Set permissions
echo "=== Setting permissions ==="
chown -R www-data:www-data ${WP_DIR}
find ${WP_DIR} -type d -exec chmod 755 {} \;
find ${WP_DIR} -type f -exec chmod 644 {} \;

# Restart PHP-FPM
systemctl restart php8.3-fpm

echo "=== Migration Complete ==="
echo ""
echo "Next steps:"
echo "1. Configure DNS: Add A record for ${DOMAIN} pointing to this VM's IP"
echo "2. Request SSL certificate: sudo certbot --nginx -d ${DOMAIN}"
echo "3. Test the site: https://${DOMAIN}"
echo ""
echo "To request SSL now (after DNS is configured):"
echo "  sudo certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m admin@${DOMAIN}"
