# Hide My WP Nginx Configuration Comparison

## Location Differences

| Server | Path |
|--------|------|
| **Old (Bitnami)** | `/opt/bitnami/apps/wordpress/conf/nginx-app.conf` |
| **New (Ubuntu)** | `/etc/nginx/snippets/hide-my-wp.conf` |

The new server follows Ubuntu's standard nginx structure where configuration snippets are stored in `/etc/nginx/snippets/` and included in the main site config at `/etc/nginx/sites-available/wordpress`.

## Configuration Differences

### Missing Rules on New Server

The old server has these additional rewrite rules that are MISSING on the new server:

1. **RevSlider plugin CSS** (line missing on new server):
   ```nginx
   rewrite ^/ext/231436b4/public/assets/css/settings\.css /wp-content/plugins/revslider/public/assets/css/settings.css?ca_pristup=skryt last;
   ```

2. **Duplicator plugin** (line missing on new server):
   ```nginx
   rewrite ^/ext/219d8031/(.*) /wp-content/plugins/duplicator/$1?ca_pristup=skryt last;
   ```

3. **WP-Optimize plugin** (line missing on new server):
   ```nginx
   rewrite ^/ext/6e235b43/(.*) /wp-content/plugins/wp-optimize/$1?ca_pristup=skryt last;
   ```

4. **PHP file blocking rules** (completely missing on new server):
   ```nginx
   #If you have a block with "location ~ \.php$"  add following two lines to the top of that block otherwise leave it unchanged
   rewrite ^/(index\.php|wp-comments-post\.php|wp-includes/js/tinymce/wp-tinymce\.php|xmlrpc\.php|wp-cron\.php|wp-login\.php|index\.php|wp-admin/|prihlaseni)(.*) /$1$2?ca_pristup=skryt break;
   rewrite ^/(.*)\.php(.*) /nothing_404_404?ca_pristup=skryt last;
   ```

### Present on Both Servers

These rules are correctly migrated:
- Cookie and argument checks for bypass
- Login page rewrite (`/prihlaseni` → `/wp-login.php`)
- wp-includes rewrite (`/lib/` → `/wp-includes/`)
- Uploads rewrite (`/file/` → `/wp-content/uploads/`)
- Generic plugins rewrite (`/ext/` → `/wp-content/plugins/`)
- Theme rewrites for hello-elementor and hello-theme-child-master
- Admin ajax rewrite
- Content rewrite (`/inc/` → `/wp-content/`)

## Impact Assessment

### Critical Missing Rules (May Break Functionality):
- **PHP file blocking** - This is a security feature that blocks direct PHP access
  - May allow bypassing Hide My WP protection if not present

### Non-Critical (Plugin-Specific):
- **RevSlider** - Only affects if RevSlider plugin is installed
- **Duplicator** - Only affects if Duplicator plugin needs obfuscated paths
- **WP-Optimize** - Only affects if WP-Optimize plugin needs obfuscated paths

## Recommendation

Add the missing PHP blocking rules to `/etc/nginx/snippets/hide-my-wp.conf` on the new server to match the old server's security level.
