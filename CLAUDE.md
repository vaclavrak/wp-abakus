# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**wp-abakus** is a WordPress deployment project migrating from a legacy Bitnami VM to modern GCP infrastructure.

**Active approach**: VM-based deployment with traditional LEMP stack on Ubuntu 24.04 VMs.

Two environments are currently active:
- **test.abakus.cz** (lab-fb-web project) - test environment
- **2026.abakus.cz** (abakus-web project) - staging, will become production abakus.cz

## Repository Structure

```
wp-abacus/
├── terraform-2026/      # Staging/Prod env (abakus-web, 2026.abakus.cz → abakus.cz)
├── scripts/             # VM bootstrap, migration, and cutover scripts
│   ├── startup.sh       # LEMP stack installation (Ubuntu 24.04, nginx, PHP 8.3, MariaDB)
│   ├── migrate-wordpress.sh  # WordPress data migration from old VM
│   └── cutover-to-production.sh  # Production cutover automation (2026.abakus.cz → abakus.cz)
├── .secrets/            # GCP service account keys (gitignored)
├── __delete/            # Old WordPress data pending cleanup (old-abakus export)
└── MIGRATION-DOCS.md    # Detailed post-migration fixes, nginx config, security hardening
```

**Note**: The test environment terraform config (`terraform/` for lab-fb-web) was removed. Test env (test.abakus.cz) is managed separately.

## Architecture

**Stack**: Ubuntu 24.04 + nginx + PHP 8.3-FPM + MariaDB 10.11

**Key Design Decisions**:
- Static external IPs managed by Terraform
- Startup script (`scripts/startup.sh`) installs full LEMP stack on VM boot
- Database credentials auto-generated and stored in `/root/.wp-credentials` on VM
- WordPress salts preserved from original site to maintain user sessions
- Automated backups via GCP snapshot schedules (daily 7d retention, weekly 30d)

**Critical Warning**: Modifying `scripts/startup.sh` triggers full VM replacement in Terraform. Use targeted applies for monitoring-only updates (see Terraform Deployment section).

## Environments

| Environment | GCP Project | Domain | VM | IP | Zone |
|-------------|-------------|--------|-----|-----|------|
| Test | lab-fb-web | test.abakus.cz | wp-abakus-test | 35.242.241.255 | europe-west3-a |
| Staging | abakus-web | 2026.abakus.cz | wp-abakus-2026 | 35.187.33.92 | europe-west1-b |
| Production | abakus-web | abakus.cz | wp-abakus-prod | TBD | TBD |
| Old (Bitnami) | abakus-web | abakus.cz | wordpresspro-1-vm | N/A | europe-west4-b |

**Project-specific authentication**:
- `terraform-2026/` (abakus-web): Requires service account at `.secrets/wp-2026-deployer.json`

## Common Commands

### SSH Access
```bash
# Test environment (lab-fb-web project)
gcloud compute ssh wp-abakus-test --zone=europe-west3-a --project=lab-fb-web

# Staging environment (abakus-web project)
gcloud compute ssh wp-abakus-2026 --zone=europe-west1-b --project=abakus-web

# Old Bitnami VM (requires service account)
gcloud auth activate-service-account --key-file=.secrets/abakus-web.json
gcloud compute ssh wordpresspro-1-vm --zone=europe-west4-b --project=abakus-web
```

### Terraform Deployment
```bash
# Staging/Production (uses service account)
cd terraform-2026
terraform init
terraform plan
terraform apply

# Safe monitoring-only update (avoids VM replacement)
terraform apply -target=google_monitoring_notification_channel.email \
  -target=google_monitoring_uptime_check_config.https \
  -target=google_monitoring_uptime_check_config.ssl_cert \
  -target=google_monitoring_alert_policy.uptime
```

### Production Cutover (2026.abakus.cz → abakus.cz)
```bash
# After DNS propagation, run on the VM:
sudo bash /root/scripts/cutover-to-production.sh

# Or copy from local and run:
gcloud compute scp scripts/cutover-to-production.sh wp-abakus-2026:/tmp/ --zone=europe-west1-b --project=abakus-web
gcloud compute ssh wp-abakus-2026 --zone=europe-west1-b --project=abakus-web -- sudo bash /tmp/cutover-to-production.sh
```

### WordPress Migration Process
```bash
# 1. Upload migration files to VM
gcloud compute scp database.sql wp-content.tar.gz VM_NAME:/tmp/wp-migration/

# 2. SSH to VM and run migration script
sudo /root/scripts/migrate-wordpress.sh

# 3. Request SSL certificate (after DNS configured)
sudo certbot --nginx -d DOMAIN -d www.DOMAIN
```

### On-VM WordPress Management
```bash
# SSH into VM first, then:

# Regenerate Elementor CSS (after URL changes)
cd /var/www/wordpress
sudo -u www-data wp eval '
$posts = array(6, 43, 59, 926);
foreach($posts as $id) {
  $css = new \Elementor\Core\Files\CSS\Post($id);
  $css->update();
}
'

# Update database URLs (test → prod)
sudo mysql wordpress -e "
UPDATE wp_options SET option_value = 'https://abakus.cz' WHERE option_name IN ('siteurl', 'home');
UPDATE wp_posts SET post_content = REPLACE(post_content, 'test.abakus.cz', 'abakus.cz');
"

# Clear all caches
sudo -u www-data wp cache flush
sudo -u www-data wp transient delete --all
sudo rm -f /var/www/wordpress/wp-content/uploads/elementor/css/*.css
sudo systemctl restart php8.3-fpm nginx

# Check fail2ban status
sudo fail2ban-client status wordpress
```

## Security Configuration

### Hide My WP Plugin
WordPress paths are obfuscated for security:
- **Login URL**: `https://DOMAIN/prihlaseni` (NOT `/wp-login.php`)
- Direct access to `/wp-admin/`, `/wp-login.php`, `/wp-content/`, `/wp-includes/` returns 404
- After login, plugin sets cookie (`eadcc=1`) allowing direct path access
- nginx rewrite rules in `/etc/nginx/snippets/hide-my-wp.conf`

**Important**: When enabling Hide My WP, uncomment the include directive in `/etc/nginx/sites-available/wordpress` and reload nginx.

### Enabled Security Features
- SSL/TLS (Let's Encrypt, auto-renewal via certbot.timer)
- fail2ban (WordPress + SSH protection)
- SSH key-only authentication (password auth disabled)
- XML-RPC blocked (`/etc/nginx/snippets/security-xmlrpc.conf`)
- Automatic security updates (unattended-upgrades)
- GCP Uptime monitoring with email alerts

### Key VM Paths
```
/var/www/wordpress/              # WordPress root
/etc/nginx/sites-available/wordpress  # Main nginx config
/etc/nginx/snippets/             # Security configs (hide-my-wp, xmlrpc, health)
/root/.wp-credentials            # Database password (auto-generated)
/root/scripts/                   # Migration and maintenance scripts
/var/log/nginx/wordpress.*.log   # Access/error logs
```

## Backups & Monitoring

**Automated Snapshots** (Terraform-managed):
- Daily: 3 AM UTC, 7-day retention
- Weekly: Sunday 4 AM UTC, 30-day retention

**Monitoring**:
- Health endpoint: `https://DOMAIN/health` (checked every 60s)
- SSL certificate check: Every 15 minutes
- Alerts sent to: rak@webeye.services
- GCP Console: [lab-fb-web](https://console.cloud.google.com/monitoring/uptime?project=lab-fb-web) | [abakus-web](https://console.cloud.google.com/monitoring/uptime?project=abakus-web)

## Production Cutover Checklist

To transition from staging (2026.abakus.cz) to production (abakus.cz):

1. ✅ VM deployed (wp-abakus-2026, IP: 35.187.33.92)
2. ✅ WordPress migrated and tested
3. ⏳ Update DNS: abakus.cz A record → 35.187.33.92
4. ⏳ Run `cutover-to-production.sh` (automates SSL, nginx, Elementor CSS, cache clearing)
5. ⏳ Final testing
6. ⏳ Decommission old Bitnami VM (wordpresspro-1-vm)

## Important Implementation Notes

- **Terraform VM replacement**: Changes to `scripts/startup.sh` trigger full VM recreation. When possible, modify VM configs directly and use targeted Terraform applies.
- **WordPress salts**: Preserved from original installation to maintain user sessions across migration.
- **Database credentials**: Auto-generated during VM startup and stored in `/root/.wp-credentials`.
- **Hide My WP**: Must manually uncomment nginx include directive after WordPress migration to avoid breaking initial setup.
- **SSL certificates**: Certbot runs automatically via systemd timer (twice daily) for renewals.
- **www redirects**: Configured to redirect www.domain → domain (non-www canonical).

## Detailed Documentation

For detailed troubleshooting and configuration reference, see **MIGRATION-DOCS.md** which contains:
- Post-migration fixes (14+ documented issues with solutions)
- Complete nginx configuration details (SSL, gzip, security headers, fastcgi)
- Hide My WP plugin configuration and path mappings
- Fail2ban brute force protection setup
- Security hardening (XML-RPC, SSH, automatic updates)
- GCP monitoring and alerting configuration
