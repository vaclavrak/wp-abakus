#!/bin/bash
# Production Cutover Script: 2026.abakus.cz → abakus.cz
# Run this AFTER DNS has propagated to 35.187.33.92
#
# Prerequisites:
#   1. DNS A record for abakus.cz pointing to 35.187.33.92
#   2. DNS A record for www.abakus.cz pointing to 35.187.33.92
#   3. SSH access to wp-abakus-2026 VM
#
# Usage:
#   sudo bash /root/scripts/cutover-to-production.sh
#
# Or run step by step manually.

set -e

OLD_DOMAIN="2026.abakus.cz"
NEW_DOMAIN="abakus.cz"
WP_PATH="/var/www/wordpress"

echo "=========================================="
echo "Production Cutover: $OLD_DOMAIN → $NEW_DOMAIN"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo)"
    exit 1
fi

# Step 1: Verify DNS
echo ""
echo "Step 1: Verifying DNS propagation..."
RESOLVED_IP=$(dig +short $NEW_DOMAIN | head -1)
EXPECTED_IP="35.187.33.92"

if [ "$RESOLVED_IP" != "$EXPECTED_IP" ]; then
    echo "ERROR: DNS not yet propagated!"
    echo "  Expected: $EXPECTED_IP"
    echo "  Got: $RESOLVED_IP"
    echo "Please wait for DNS propagation and try again."
    exit 1
fi
echo "  ✓ DNS verified: $NEW_DOMAIN → $RESOLVED_IP"

# Step 2: Request SSL Certificate
echo ""
echo "Step 2: Requesting SSL certificate..."
certbot --nginx -d $NEW_DOMAIN -d www.$NEW_DOMAIN --non-interactive --agree-tos --redirect
echo "  ✓ SSL certificate obtained"

# Step 3: Update nginx server_name
echo ""
echo "Step 3: Updating nginx configuration..."
sed -i "s/server_name ${OLD_DOMAIN}/server_name ${NEW_DOMAIN} www.${NEW_DOMAIN}/g" /etc/nginx/sites-available/wordpress
nginx -t
systemctl reload nginx
echo "  ✓ Nginx configuration updated"

# Step 4: Update database URLs (SKIP - already done)
# echo ""
# echo "Step 4: Updating database URLs..."
# mysql wordpress -e "
# UPDATE wp_options SET option_value = 'https://${NEW_DOMAIN}' WHERE option_name IN ('siteurl', 'home');
# UPDATE wp_posts SET post_content = REPLACE(post_content, '${OLD_DOMAIN}', '${NEW_DOMAIN}');
# UPDATE wp_posts SET guid = REPLACE(guid, '${OLD_DOMAIN}', '${NEW_DOMAIN}');
# UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '${OLD_DOMAIN}', '${NEW_DOMAIN}');
# UPDATE wp_options SET option_value = REPLACE(option_value, '${OLD_DOMAIN}', '${NEW_DOMAIN}');
# "
# echo "  ✓ Database URLs updated"
echo ""
echo "Step 4: Database URLs - SKIPPED (already configured)"

# Step 5: Regenerate Elementor CSS
echo ""
echo "Step 5: Regenerating Elementor CSS..."
cd $WP_PATH
sudo -u www-data wp eval '
$posts = array(6, 43, 59, 926);
foreach($posts as $id) {
    $css = new \Elementor\Core\Files\CSS\Post($id);
    $css->update();
    echo "  Regenerated CSS for post $id\n";
}
'
echo "  ✓ Elementor CSS regenerated"

# Step 6: Clear caches
echo ""
echo "Step 6: Clearing caches..."
cd $WP_PATH
sudo -u www-data wp cache flush
sudo -u www-data wp transient delete --all
rm -f ${WP_PATH}/wp-content/uploads/elementor/css/*.css 2>/dev/null || true
systemctl restart php8.3-fpm nginx
echo "  ✓ Caches cleared"

# Step 7: Verify
echo ""
echo "Step 7: Verifying site..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://${NEW_DOMAIN}/)
if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✓ Site responding with HTTP 200"
else
    echo "  ⚠ Site returned HTTP $HTTP_CODE (may still be OK)"
fi

HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://${NEW_DOMAIN}/health)
if [ "$HEALTH_CODE" = "200" ]; then
    echo "  ✓ Health endpoint OK"
else
    echo "  ⚠ Health endpoint returned HTTP $HEALTH_CODE"
fi

echo ""
echo "=========================================="
echo "Cutover Complete!"
echo "=========================================="
echo ""
echo "Site is now live at: https://${NEW_DOMAIN}"
echo ""
echo "Next steps:"
echo "  1. Test the site thoroughly"
echo "  2. Verify login at https://${NEW_DOMAIN}/prihlaseni"
echo "  3. Update Terraform monitoring (run terraform apply with -target)"
echo "  4. Consider decommissioning old Bitnami VM (wordpresspro-1-vm)"
echo ""