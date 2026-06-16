# WordPress Migration Documentation

## Overview
Migration from old Bitnami VM (abakus-web project) to new Ubuntu 24.04 LEMP stack.

## Environments

| Environment | GCP Project | Domain | VM Name | Status |
|-------------|-------------|--------|---------|--------|
| **Test** | lab-fb-web | test.abakus.cz | wp-abakus-test | ✅ Complete |
| **Staging** | abakus-web | 2026.abakus.cz | wp-abakus-2026 | ✅ Complete |
| **Production** | abakus-web | abakus.cz | (same as staging) | ⏳ DNS switch pending |
| **Old (Bitnami)** | abakus-web | abakus.cz | wordpresspro-1-vm | Running (to be decommissioned) |

## Staging Environment Details (2026.abakus.cz)

- **VM IP**: 35.187.33.92
- **Region/Zone**: europe-west1-b (Belgium)
- **Machine Type**: e2-small (2 vCPU, 2GB RAM)
- **OS**: Ubuntu 24.04 LTS
- **Disk**: 20GB pd-balanced
- **Deployed**: 2026-03-21
- **WordPress**: 6.9.4
- **PHP**: 8.3.6
- **MariaDB**: 10.11.14
- **nginx**: 1.24.0

### Active Plugins
- Elementor + Elementor Pro
- Element Pack (bdthemes)
- Hide My WP
- Rank Math SEO
- Cookie Law Info
- WP Mail SMTP
- Disable Comments
- Duplicate Post

### Migration from Old Server
- **Source**: wordpresspro-1-vm (Bitnami WordPress Pro 5.6.2, Debian 10)
- **Database**: Exported and imported with URL replacements
- **wp-content**: Full copy (themes, plugins, uploads)
- **Salts**: Preserved from original wp-config.php

## Test Environment Details (test.abakus.cz)

- **VM IP**: 35.242.241.255
- **Region/Zone**: europe-west3-a
- **Machine Type**: e2-small (2 vCPU, 2GB RAM)
- **OS**: Ubuntu 24.04 LTS
- **Disk**: 20GB pd-balanced

## Stack Components

| Component | Version |
|-----------|---------|
| nginx | 1.24.0 |
| PHP-FPM | 8.3 |
| MariaDB | 10.11 |
| WordPress | Latest |
| Certbot | Let's Encrypt |

---

## Post-Migration Issues & Fixes

### ⚠️ Hide My WP Nginx Configuration Location (Developer Note)

**Developer's concern:** "Nginx configuration file is at old location `/opt/bitnami/apps/wordpress/conf/nginx-app.conf` and I can't find it on the new server. The settings for Hide My WP plugin are inserted there."

**Answer:** ✅ The configuration EXISTS on the new server, just in a different location:

| Old Server | New Server |
|------------|------------|
| `/opt/bitnami/apps/wordpress/conf/nginx-app.conf` | `/etc/nginx/snippets/hide-my-wp.conf` |

The new server follows Ubuntu's modular nginx structure. The Hide My WP snippet is included in `/etc/nginx/sites-available/wordpress`.

**⚠️ Critical Issue:** The migration is **incomplete** - PHP file blocking rules are missing, creating a security gap. See section "Hide My WP Nginx Configuration" below for full details and fix.

---

## Post-Migration Fixes Applied

### 1. Database URL Replacement
All URLs in database replaced from `abakus.cz` → `test.abakus.cz`:
```sql
UPDATE wp_posts SET post_content = REPLACE(post_content, 'https://abakus.cz', 'https://test.abakus.cz');
UPDATE wp_posts SET guid = REPLACE(guid, 'https://abakus.cz', 'https://test.abakus.cz');
UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, 'https://abakus.cz', 'https://test.abakus.cz');
UPDATE wp_options SET option_value = REPLACE(option_value, 'https://abakus.cz', 'https://test.abakus.cz');
```

### 2. Hide My WP Plugin Re-enabled
Plugin was initially disabled due to 404 errors (nginx rewrite rules were missing).
Now re-enabled with proper nginx configuration.

**How it works:**
- Login page: `/prihlaseni` (rewrites to `/wp-login.php`)
- Direct access to `/wp-admin/`, `/wp-login.php`, `/wp-content/`, `/wp-includes/` is blocked (404)
- After logging in via `/prihlaseni`, the plugin sets a bypass cookie (`eadcc=1`)
- With the cookie, direct paths become accessible

**Nginx configuration added:**
- `/etc/nginx/snippets/hide-my-wp.conf` - rewrite rules
- Included in `/etc/nginx/sites-available/wordpress`

### 3. Active Plugins Array Fixed
Corrupted serialized array with empty entries was fixed:
```php
// Fixed active plugins (8 plugins)
a:8:{
  i:0;s:47:"bdthemes-element-pack/bdthemes-element-pack.php";
  i:1;s:35:"cookie-law-info/cookie-law-info.php";
  i:2;s:37:"disable-comments/disable-comments.php";
  i:3;s:33:"duplicate-post/duplicate-post.php";
  i:4;s:31:"elementor-pro/elementor-pro.php";
  i:5;s:23:"elementor/elementor.php";
  i:6;s:30:"seo-by-rank-math/rank-math.php";
  i:7;s:29:"wp-mail-smtp/wp_mail_smtp.php";
}
```

### 4. Elementor CSS Regeneration
CSS files were not generated after migration. Fixed by:
```php
// Force regeneration via WP-CLI
$post_css = new \Elementor\Core\Files\CSS\Post($post_id);
$post_css->update();
```

Generated files:
- `/wp-content/uploads/elementor/css/post-6.css` (kit)
- `/wp-content/uploads/elementor/css/post-43.css` (header)
- `/wp-content/uploads/elementor/css/post-59.css` (homepage)
- `/wp-content/uploads/elementor/css/post-926.css` (footer)

### 5. File Ownership Mismatch (daemon vs www-data)

**Issue:** Files migrated from old Bitnami server retained `daemon:daemon` ownership, but new Ubuntu server runs PHP-FPM as `www-data` user.

**Old Server (Bitnami):**
- PHP-FPM runs as `daemon` user (configured in `/opt/bitnami/php/etc/php-fpm.conf`)
- All uploads owned by `daemon:daemon`

**New Server (Ubuntu 24.04):**
- PHP-FPM runs as `www-data` user (standard Ubuntu configuration)
- Migrated files kept original `daemon:daemon` ownership
- **Result:** WordPress cannot write to uploads directory

**Fix Applied:**
```bash
sudo chown -R www-data:www-data /var/www/wordpress/wp-content/uploads/
```

**Permissions After Fix:**
```
drwxrwsr-x www-data www-data /var/www/wordpress/wp-content/uploads/
```

Now WordPress can:
- Upload new media files
- Edit/delete existing media
- Generate thumbnails
- Modify uploaded content

### 6. Duplicate Directories in WordPress Root (Deleted)

**Issue:** Duplicate `plugins/`, `themes/`, and `uploads/` directories found in `/var/www/wordpress/` root (should only be in `wp-content/`).

**Investigation:**
```bash
# Found duplicate directories
ls -la /var/www/wordpress/
drwxrwxr-x plugins/  (186MB) - duplicate of wp-content/plugins/
drwxrwxr-x themes/   (12MB)  - duplicate of wp-content/themes/
drwxrwxr-x uploads/  (194MB) - duplicate of wp-content/uploads/

# Verified they were NOT symlinks
file /var/www/wordpress/plugins  # directory (not symlink)

# Verified WordPress uses correct location
wp plugin list  # Shows plugins from wp-content/plugins/
```

**Cause:** Likely created during migration when wp-content.tar.gz was extracted in wrong location. Files had old Bitnami ownership (`daemon:daemon`, `ubuntu:daemon`).

**Resolution:**
```bash
sudo rm -rf /var/www/wordpress/plugins /var/www/wordpress/themes /var/www/wordpress/uploads
```

**Result:**
- Space freed: ~400MB (5.6GB → 5.2GB)
- WordPress verified working after deletion
- All plugins and themes functioning correctly

### 7. Abakus User Permissions for wp-content

**Issue:** Abakus user (used for SFTP/SSH file transfers) could not modify files in `/var/www/wordpress/wp-content/`.

**Fix Applied:**
```bash
# Add Abakus to www-data group
sudo usermod -aG www-data Abakus

# Set group ownership and permissions
sudo chown -R www-data:www-data /var/www/wordpress/wp-content/
sudo find /var/www/wordpress/wp-content/ -type d -exec chmod 775 {} \;
sudo find /var/www/wordpress/wp-content/ -type f -exec chmod 664 {} \;
sudo find /var/www/wordpress/wp-content/ -type d -exec chmod g+s {} \;
```

**Result:**
- Directories: `775` (rwxrwsr-x) - Both www-data and Abakus can write
- Files: `664` (rw-rw-r--) - Both www-data and Abakus can modify
- Setgid bit ensures new files inherit `www-data` group

Now both PHP-FPM (www-data) and Abakus user can read/write files.

### 8. SSL Parameters Missing (Fixed)

**Developer's Question:** "Are SSL session cache, ssl_dhparam and other SSL parameters configured on the server? Is there an include for Certbot's options-ssl-nginx.conf?"

**Issue:** SSL optimization parameters were not configured in nginx - no SSL session cache, DH parameters, or Certbot SSL options included.

**Investigation:**
```bash
# Certbot files exist but not included
ls /etc/letsencrypt/options-ssl-nginx.conf  # ✅ exists
ls /etc/letsencrypt/ssl-dhparams.pem         # ✅ exists

# But not referenced in nginx config
grep options-ssl-nginx /etc/nginx/sites-available/wordpress  # ❌ missing
grep ssl_dhparam /etc/nginx/sites-available/wordpress        # ❌ missing
```

**Before (nginx config had only):**
```nginx
listen 443 ssl http2;
ssl_certificate /etc/letsencrypt/live/2026.abakus.cz/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/2026.abakus.cz/privkey.pem;
# ❌ No SSL optimization parameters
# ❌ No session caching
# ❌ No DH parameters
```

**Comparison with Old Bitnami Server:**
```nginx
ssl_session_cache shared:SSL:1m;       # 1MB cache
ssl_session_timeout 5m;                 # 5 minutes
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
```

**Fix Applied:**
```bash
# Edit /etc/nginx/sites-available/wordpress
# Added after ssl_certificate_key line:
include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

# Test and reload
sudo nginx -t && sudo systemctl reload nginx
```

**After (complete SSL configuration):**
```nginx
listen 443 ssl http2;
ssl_certificate /etc/letsencrypt/live/2026.abakus.cz/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/2026.abakus.cz/privkey.pem;
include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
```

**SSL Parameters Now Active** (from options-ssl-nginx.conf):
```nginx
# Performance Optimization
ssl_session_cache shared:le_nginx_SSL:10m;     # 10MB cache (~40k sessions)
ssl_session_timeout 1440m;                      # 24 hours (was 5min on old server)
ssl_session_tickets off;                        # Disabled for security

# Security
ssl_protocols TLSv1.2 TLSv1.3;                 # Modern protocols only
ssl_prefer_server_ciphers off;                  # Let client choose (TLS 1.3 best practice)

# Mozilla-recommended cipher suites
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
```

**Verification:**
```bash
# Test SSL connection
echo | openssl s_client -connect localhost:443 -servername 2026.abakus.cz 2>&1 | grep -E 'Protocol|Cipher'
# Result:
# Protocol: TLSv1.3
# Cipher: TLS_AES_256_GCM_SHA384

# Test from outside
curl -vI https://2026.abakus.cz/ 2>&1 | grep "SSL connection"
# Result: HTTP 200 OK
```

**Comparison: Old vs New Server**

| Parameter | Old Bitnami | New Ubuntu |
|-----------|-------------|------------|
| Session Cache | 1MB | 10MB (10x larger) |
| Session Timeout | 5 minutes | 1440 minutes (288x longer) |
| Protocols | TLS 1.0-1.3 | TLS 1.2-1.3 (more secure) |
| DH Parameters | Unknown | 2048-bit |
| Cipher Suites | `HIGH:!aNULL:!MD5` | Mozilla-recommended modern ciphers |

**Benefits:**
- ✅ **Performance**: 10MB session cache reduces SSL handshake CPU usage
- ✅ **Security**: TLS 1.3 with modern cipher suites (AEAD-only)
- ✅ **Forward Secrecy**: DH parameters protect past sessions
- ✅ **Better than old server**: Larger cache, longer timeout, stronger ciphers
- ✅ **Future-proof**: Certbot auto-updates these files with security improvements

**Certificate Information:**
```
Certificate Name: 2026.abakus.cz
Key Type: ECDSA (faster than RSA)
Expiry Date: 2026-06-19 (auto-renewal enabled)
Certificate Path: /etc/letsencrypt/live/2026.abakus.cz/fullchain.pem
```

**Important Notes:**
- Files `/etc/letsencrypt/options-ssl-nginx.conf` and `ssl-dhparams.pem` are managed by Certbot
- **Do not modify these files manually** or Certbot will stop updating them
- Certbot will maintain these includes during certificate renewals
- Same fix should be applied to test.abakus.cz environment

### 9. Gzip Compression Disabled for CSS, JS, JSON, SVG (Fixed)

**Developer's Question:** "I noticed that gzip is enabled, but gzip_types look commented out - is this intentional, or should they be activated for CSS, JS, JSON and SVG?"

**Issue:** Gzip was enabled (`gzip on;`) but all gzip_types were commented out, so only HTML was being compressed (nginx default). CSS, JS, JSON, XML, and SVG files were being served uncompressed.

**Investigation:**
```bash
# Check nginx config
cat /etc/nginx/nginx.conf | grep -A10 gzip
# Result: All gzip_types commented out with #

# Test compression
curl -I -H 'Accept-Encoding: gzip' https://2026.abakus.cz/lib/js/jquery/jquery.min.js
# Result: No content-encoding header

# File sizes
Uncompressed: 87,553 bytes
Compressed: 87,553 bytes (same - not compressed!)
```

**Comparison with Old Bitnami Server:**
Old server had full gzip configuration:
```nginx
gzip on;
gzip_http_version 1.1;
gzip_comp_level 2;
gzip_proxied any;
gzip_vary on;
gzip_types text/plain
           text/xml
           text/css
           text/javascript
           application/json
           application/javascript
           application/x-javascript
           application/ecmascript
           application/xml
           application/rss+xml;
```

**Fix Applied:**
```bash
# Uncommented in /etc/nginx/nginx.conf
gzip on;
gzip_vary on;                    # Adds Vary: Accept-Encoding header
gzip_proxied any;                # Enable compression for proxied requests
gzip_comp_level 6;               # Compression level (1-9, 6 is good balance)

# File types to compress
gzip_types text/plain
           text/css
           application/json
           application/javascript
           text/xml
           application/xml
           application/xml+rss
           text/javascript
           image/svg+xml;         # Added for SVG support
```

**Verification After Fix:**
```bash
# Test JavaScript compression
curl -I -H 'Accept-Encoding: gzip' https://2026.abakus.cz/lib/js/jquery/jquery.min.js
# Result: content-encoding: gzip ✅

# Compare sizes
Uncompressed: 87,553 bytes
Compressed:   30,419 bytes
Savings:      65.3% smaller!

# Test CSS
curl -I -H 'Accept-Encoding: gzip' https://2026.abakus.cz/skin/style.css
# Result: content-encoding: gzip ✅

# Test HTML
curl -I -H 'Accept-Encoding: gzip' https://2026.abakus.cz/
# Result: content-encoding: gzip ✅
```

**Compression Results by File Type:**

| File Type | MIME Type | Compressed? | Typical Savings |
|-----------|-----------|-------------|-----------------|
| HTML | text/html | ✅ | 60-80% |
| CSS | text/css | ✅ | 70-85% |
| JavaScript | application/javascript | ✅ | 60-75% |
| JSON | application/json | ✅ | 70-90% |
| XML | application/xml | ✅ | 70-85% |
| SVG | image/svg+xml | ✅ | 70-85% |
| Images (JPG/PNG) | image/* | ❌ | N/A (already compressed) |

**Benefits:**
- ✅ **Page load speed**: 60-70% smaller file transfers
- ✅ **Bandwidth savings**: Reduced data transfer costs
- ✅ **User experience**: Faster page loads, especially on slow connections
- ✅ **SEO**: Google ranks faster sites higher
- ✅ **Mobile**: Critical for mobile users with limited bandwidth

**Configuration Details:**
- `gzip_comp_level 6`: Good balance between compression ratio and CPU usage (1=fastest/least, 9=slowest/most)
- `gzip_vary on`: Adds `Vary: Accept-Encoding` header for proper caching
- `gzip_proxied any`: Enables compression for requests through proxies/CDNs
- Files are compressed on-the-fly by nginx for each request

**Performance Impact:**
- CPU usage: Minimal increase (level 6 is efficient)
- Memory: No significant impact
- Response time: Slightly longer compression time, but much faster transfer
- Overall: Net positive - faster page loads despite compression overhead

### 10. Server Version Disclosure (server_tokens) - Security Issue (Fixed)

**Developer's Question:** "Is server_tokens set to off? So that the nginx version doesn't appear in responses."

**Issue:** `server_tokens` was commented out in nginx.conf, causing nginx to expose its version number in HTTP headers - a security vulnerability.

**Security Risk:**
Exposing server version helps attackers:
- Identify known vulnerabilities for specific nginx versions
- Craft targeted exploits
- Gather reconnaissance information

**Investigation:**
```bash
# Check configuration
grep server_tokens /etc/nginx/nginx.conf
# Result: # server_tokens off; (commented out - using default 'on')

# Test HTTP headers
curl -I https://2026.abakus.cz/
# Result: server: nginx/1.24.0 (Ubuntu) ⚠️ Version exposed!
```

**Comparison with Old Server:**
```bash
curl -I https://abakus.cz/
# Old server: nginx/1.18.0 ⚠️ Also exposes version
```

**Fix Applied:**
```bash
# Edit /etc/nginx/nginx.conf
# Uncommented:
server_tokens off;

# Reload nginx
sudo nginx -t && sudo systemctl reload nginx
```

**Verification After Fix:**
```bash
# Test headers
curl -I https://2026.abakus.cz/
# Result: server: nginx ✅ Version hidden!

# Test on error pages
curl -I https://2026.abakus.cz/nonexistent
# Result: server: nginx ✅ Still hidden on 404 errors
```

**Before vs After:**

| Location | Before | After |
|----------|--------|-------|
| Normal response | `nginx/1.24.0 (Ubuntu)` | `nginx` |
| Error pages | `nginx/1.24.0 (Ubuntu)` | `nginx` |
| Old server | `nginx/1.18.0` | N/A |

**Benefits:**
- ✅ **Security**: Prevents version fingerprinting
- ✅ **Compliance**: Security best practice (OWASP recommendation)
- ✅ **Better than old server**: Old server still exposes version
- ✅ **Defense in depth**: Reduces information available to attackers

**Important Notes:**
- This only hides the version in headers, not in error pages content
- Combined with other security measures (fail2ban, SSL, etc.) for defense in depth
- Should be applied to test environment as well

**Related Security Headers (already configured):**
```nginx
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
```

### 11. HSTS Header Missing - Security Issue (Fixed)

**Developer's Question:** "Is the Strict-Transport-Security header configured anywhere?"

**Issue:** HSTS (HTTP Strict-Transport-Security) header was not configured. This header tells browsers to only access the site via HTTPS, preventing protocol downgrade attacks.

**Security Risk Without HSTS:**
- Man-in-the-middle attacks possible via HTTP
- Users can be redirected to HTTP version
- No protection against SSL stripping attacks
- Session hijacking via unencrypted connections

**Investigation:**
```bash
# Check nginx configuration
grep -r 'Strict-Transport-Security' /etc/nginx/
# Result: Not found ❌

# Test HTTP headers
curl -I https://2026.abakus.cz/ | grep -i strict
# Result: No HSTS header ❌

# Check old server
curl -I https://abakus.cz/ | grep -i strict
# Result: Old server also has no HSTS ❌
```

**Fix Applied:**
```bash
# Added to /etc/nginx/sites-available/wordpress
# In the Security headers section:
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

**HSTS Configuration Details:**
```nginx
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

**Parameters Explained:**
- `max-age=31536000`: Browser remembers for 1 year (365 days)
- `includeSubDomains`: Applies to all subdomains (www.*, etc.)
- `always`: Send header even on error responses

**Note:** Did NOT include `preload` directive:
- Preload requires manual submission to HSTS preload list
- Should only be added if site will ALWAYS use HTTPS
- Can be added later if desired: `preload`

**Verification After Fix:**
```bash
# Test HSTS header
curl -I https://2026.abakus.cz/ | grep -i strict
# Result: strict-transport-security: max-age=31536000; includeSubDomains ✅

# All security headers now present:
x-frame-options: SAMEORIGIN
x-content-type-options: nosniff
x-xss-protection: 1; mode=block
strict-transport-security: max-age=31536000; includeSubDomains ✅
```

**How HSTS Works:**
1. **First Visit:** Browser connects via HTTPS, receives HSTS header
2. **Subsequent Visits:** Browser automatically uses HTTPS for 1 year
3. **HTTP Attempts:** Browser converts http:// to https:// automatically
4. **Protection:** Prevents man-in-the-middle attacks and SSL stripping

**Security Benefits:**
- ✅ **Prevents protocol downgrade attacks**: Forces HTTPS
- ✅ **Protection from SSL stripping**: Can't be redirected to HTTP
- ✅ **Improved security**: Browsers enforce HTTPS for 1 year
- ✅ **Better than old server**: Old server has no HSTS protection
- ✅ **Industry best practice**: Required for modern security standards

**Testing HSTS:**
```bash
# Browser will now automatically use HTTPS for:
http://2026.abakus.cz → https://2026.abakus.cz (auto-converted)
http://www.2026.abakus.cz → https://2026.abakus.cz (auto-converted)
```

**Important Notes:**
- HSTS only works after first HTTPS visit
- Browser caches the policy for 1 year
- To clear HSTS: Browser settings → Clear security policies
- Should be applied to test environment as well
- Consider adding `preload` after production cutover if site will always use HTTPS

**Complete Security Headers Summary:**

| Header | Purpose | Status |
|--------|---------|--------|
| X-Frame-Options | Prevents clickjacking | ✅ |
| X-Content-Type-Options | Prevents MIME sniffing | ✅ |
| X-XSS-Protection | XSS filter | ✅ |
| Strict-Transport-Security | Forces HTTPS | ✅ NEW |
| Server (version hidden) | Reduces fingerprinting | ✅ |

### 12. Security Headers Missing on Static Files - Nginx Inheritance Issue (Fixed)

**Developer's Question:** "In the location block for static files, custom add_header is used, which in nginx overrides security headers from the parent context - is this handled, or should the headers be repeated there?"

**Issue:** This is a critical nginx configuration gotcha. When using `add_header` in a child location block, nginx **completely overrides** all `add_header` directives from parent contexts. The static files location block had its own `add_header Cache-Control`, which caused all security headers from the server block to be lost.

**Nginx Inheritance Behavior:**
```nginx
server {
    add_header X-Frame-Options "SAMEORIGIN" always;     # Parent context

    location ~* \.(js|css)$ {
        add_header Cache-Control "public";               # Child context
        # ❌ X-Frame-Options is NOT inherited!
        # ❌ All parent add_header directives are overridden!
    }
}
```

**Investigation:**
```bash
# Check static files location block
cat /etc/nginx/sites-available/wordpress | grep -A5 "Static file caching"
# Result:
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
    # ❌ Only Cache-Control, no security headers!
}

# Test HTML page (goes through PHP)
curl -I https://2026.abakus.cz/ | grep -i strict
# Result: strict-transport-security: max-age=31536000; includeSubDomains ✅

# Test JavaScript file (static file)
curl -I 'https://2026.abakus.cz/wp-includes/js/jquery/jquery.min.js?ca_pristup=skryt'
# Result: cache-control: public, immutable
# Result: NO security headers! ❌

# Test CSS file (static file)
curl -I 'https://2026.abakus.cz/wp-includes/css/dashicons.min.css?ca_pristup=skryt'
# Result: cache-control: public, immutable
# Result: NO security headers! ❌
```

**Security Impact:**
Static files (JS, CSS, images, fonts) were served WITHOUT:
- ❌ X-Frame-Options (clickjacking protection)
- ❌ X-Content-Type-Options (MIME sniffing protection)
- ❌ X-XSS-Protection (XSS filter)
- ❌ Strict-Transport-Security (HTTPS enforcement)

**Fix Applied:**
```nginx
# /etc/nginx/sites-available/wordpress
# Static file caching location block now includes ALL headers:
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

**Verification After Fix:**
```bash
# Test JavaScript file
curl -I 'https://2026.abakus.cz/wp-includes/js/jquery/jquery.min.js?ca_pristup=skryt'
# Result:
cache-control: max-age=2592000
cache-control: public, immutable
x-frame-options: SAMEORIGIN ✅
x-content-type-options: nosniff ✅
x-xss-protection: 1; mode=block ✅
strict-transport-security: max-age=31536000; includeSubDomains ✅

# Test CSS file
curl -I 'https://2026.abakus.cz/wp-includes/css/dashicons.min.css?ca_pristup=skryt'
# Result:
cache-control: max-age=2592000
cache-control: public, immutable
x-frame-options: SAMEORIGIN ✅
x-content-type-options: nosniff ✅
x-xss-protection: 1; mode=block ✅
strict-transport-security: max-age=31536000; includeSubDomains ✅

# Test PNG image
curl -I 'https://2026.abakus.cz/wp-includes/images/w-logo-blue.png'
# Result: All 4 security headers present ✅
```

**Understanding Nginx add_header Inheritance:**

| Scenario | Result |
|----------|--------|
| Server block has `add_header X` | All locations inherit X |
| Location block has NO `add_header` | Inherits all from parent ✅ |
| Location block has `add_header Y` | ONLY Y, parent headers LOST ❌ |
| Location needs both X and Y | Must repeat all headers in location ✅ |

**Why This Matters:**
This is one of the most common nginx security misconfigurations. Many admins add caching headers to static files without realizing it breaks security header inheritance.

**Complete Security Headers by File Type:**

| File Type | Cache Headers | Security Headers | Status |
|-----------|---------------|------------------|--------|
| HTML (PHP) | No | 4 headers | ✅ |
| JavaScript | Yes (30d) | 4 headers | ✅ FIXED |
| CSS | Yes (30d) | 4 headers | ✅ FIXED |
| Images (PNG/JPG/GIF) | Yes (30d) | 4 headers | ✅ FIXED |
| Fonts (WOFF/WOFF2) | Yes (30d) | 4 headers | ✅ FIXED |
| SVG | Yes (30d) | 4 headers | ✅ FIXED |

**Important Notes:**
- This fix must be applied to any location block that uses `add_header`
- Alternative: Use nginx modules that don't override (headers-more module)
- This should be applied to test environment as well
- Always test static files specifically when configuring security headers

**Related Nginx Documentation:**
- "If either add_header directive is used in a child context, all parent add_header directives are ignored"
- Source: http://nginx.org/en/docs/http/ngx_http_headers_module.html#add_header

### 13. Duplicate Fastcgi Parameters in PHP Block (Cleaned Up)

**Developer's Question:** "In the PHP location block, fastcgi parameters and SCRIPT_FILENAME are defined multiple times (through fastcgi-php.conf and manually) - is this intentional, or could it be cleaned up?"

**Issue:** The PHP location block had redundant and duplicate fastcgi parameter definitions, making the configuration unnecessarily complex.

**Configuration Before Cleanup:**
```nginx
location ~ \.php$ {
    include snippets/fastcgi-php.conf;          # Includes fastcgi.conf
    fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;  # DUPLICATE
    include fastcgi_params;                     # REDUNDANT
}
```

**What Was Included:**

1. **`snippets/fastcgi-php.conf`** includes:
   - `fastcgi.conf` (standard nginx file)

2. **`fastcgi.conf`** contains:
   - `SCRIPT_FILENAME` parameter ✅
   - All standard fastcgi parameters ✅

3. **Manual `fastcgi_param SCRIPT_FILENAME`**:
   - Duplicates what's already in fastcgi.conf ❌

4. **`include fastcgi_params;`**:
   - Redundant - all these params are already in fastcgi.conf ❌

**Understanding nginx fastcgi files:**

| File | Contains |
|------|----------|
| `fastcgi.conf` | SCRIPT_FILENAME + all standard params |
| `fastcgi_params` | All standard params WITHOUT SCRIPT_FILENAME |

**The Problem:**
- `SCRIPT_FILENAME` was defined **twice** (in fastcgi.conf and manually)
- All fastcgi parameters were included **twice** (via fastcgi.conf and fastcgi_params)
- Configuration was unnecessarily verbose and confusing

**Cleanup Applied:**
```nginx
location ~ \.php$ {
    include snippets/fastcgi-php.conf;       # This is enough!
    fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
}
```

**Why This Works:**
```
snippets/fastcgi-php.conf
└── includes fastcgi.conf
    ├── SCRIPT_FILENAME = $document_root$fastcgi_script_name
    ├── QUERY_STRING = $query_string
    ├── REQUEST_METHOD = $request_method
    ├── CONTENT_TYPE = $content_type
    └── ... (all other fastcgi parameters)
```

Everything needed is already included via `snippets/fastcgi-php.conf`!

**What `snippets/fastcgi-php.conf` Provides:**
```nginx
# From /etc/nginx/snippets/fastcgi-php.conf:
fastcgi_split_path_info ^(.+?\.php)(/.*)$;
try_files $fastcgi_script_name =404;
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
fastcgi_index index.php;
include fastcgi.conf;  # ← This includes SCRIPT_FILENAME + all params
```

**Verification After Cleanup:**
```bash
# Test nginx configuration
sudo nginx -t
# Result: configuration test is successful ✅

# Reload nginx
sudo systemctl reload nginx
# Result: reloaded successfully ✅

# Test website
curl -I https://2026.abakus.cz/
# Result: HTTP/2 200 ✅

# Test PHP execution
curl -s https://2026.abakus.cz/ | head -20
# Result: HTML output, PHP working ✅
```

**Benefits of Cleanup:**
- ✅ **Cleaner configuration**: 2 lines instead of 4
- ✅ **No duplication**: Each parameter defined once
- ✅ **Easier to maintain**: Less code to understand
- ✅ **No functionality change**: Works exactly the same
- ✅ **Best practice**: Uses standard nginx includes

**Configuration Comparison:**

| Aspect | Before | After |
|--------|--------|-------|
| Lines of code | 4 lines | 2 lines |
| SCRIPT_FILENAME | Defined 2x | Defined 1x ✅ |
| Fastcgi params | Included 2x | Included 1x ✅ |
| Clarity | Confusing | Clear ✅ |

**Important Notes:**
- This cleanup is purely cosmetic - functionality unchanged
- Both configurations work identically
- The cleaner version is easier to maintain
- Should be applied to test environment as well

**When Would You Need Manual Parameters?**
Only if you need to override or add custom parameters not in fastcgi.conf, for example:
```nginx
fastcgi_param PHP_VALUE "upload_max_filesize=100M";  # Custom override
```

But for standard WordPress, `snippets/fastcgi-php.conf` is sufficient.

### 14. Custom Fonts Fix
Elementor Pro custom fonts (@font-face) were not being injected.
Created `/wp-content/themes/hello-theme-child-master/custom-fonts.php`:

```php
<?php
add_action("wp_head", function() {
?>
<style id="custom-fonts-fix">
@font-face { font-family: "Source Sans Pro"; font-weight: 300; src: url("/wp-content/uploads/2025/08/sourcesanspro-light-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Sans Pro"; font-weight: 400; src: url("/wp-content/uploads/2025/08/sourcesanspro-regular-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Sans Pro"; font-weight: 600; src: url("/wp-content/uploads/2025/08/sourcesanspro-semibold-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Sans Pro"; font-weight: 700; src: url("/wp-content/uploads/2025/08/sourcesanspro-bold-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Sans Pro"; font-weight: 900; src: url("/wp-content/uploads/2025/08/sourcesanspro-black-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Serif Pro"; font-weight: 400; src: url("/wp-content/uploads/2025/08/sourceserifpro-regular-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Serif Pro"; font-weight: 600; src: url("/wp-content/uploads/2025/08/sourceserifpro-semibold-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Serif Pro"; font-weight: 700; src: url("/wp-content/uploads/2025/08/sourceserifpro-bold-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Serif Pro"; font-weight: 900; src: url("/wp-content/uploads/2025/08/sourceserifpro-black-webfont.woff2") format("woff2"); }
@font-face { font-family: "Source Serif Pro"; font-style: italic; font-weight: 700; src: url("/wp-content/uploads/2025/08/sourceserifpro-bolditalic-webfont.woff2") format("woff2"); }
</style>
<?php
}, 1);
```

Added to functions.php:
```php
require_once __DIR__ . '/custom-fonts.php';
```

---

## Files Modified on VM

### Theme Files
- `/var/www/wordpress/wp-content/themes/hello-theme-child-master/custom-fonts.php` (new)
- `/var/www/wordpress/wp-content/themes/hello-theme-child-master/functions.php` (added require)

### Nginx Configuration
- `/etc/nginx/sites-available/wordpress` (SSL configured by certbot, Hide My WP rules)
- `/etc/nginx/snippets/hide-my-wp.conf` (Hide My WP rewrite rules)

### WordPress Configuration
- `/var/www/wordpress/wp-config.php` (generated by migrate-wordpress.sh)

---

## Production Cutover Checklist (2026.abakus.cz → abakus.cz)

Staging VM wp-abakus-2026 is ready. Production cutover uses the same VM.

### Pre-cutover Testing
- [x] Verify staging site (2026.abakus.cz) is working correctly
- [x] Test WordPress admin login via /prihlaseni
- [x] Check all pages render properly
- [x] Verify Elementor content displays correctly
- [ ] Verify contact forms work
- [ ] Test all critical functionality

### Cutover Steps
1. Update DNS: Point abakus.cz A record to 35.187.33.92
2. Wait for DNS propagation (check with `dig abakus.cz`)
3. Request SSL certificate:
   ```bash
   sudo certbot --nginx -d abakus.cz -d www.abakus.cz
   ```
4. Update nginx server_name:
   ```bash
   sudo sed -i 's/2026.abakus.cz/abakus.cz/g' /etc/nginx/sites-available/wordpress
   sudo nginx -t && sudo systemctl reload nginx
   ```
5. Update database URLs:
   ```bash
   sudo mysql wordpress -e "
   UPDATE wp_options SET option_value = 'https://abakus.cz' WHERE option_name IN ('siteurl', 'home');
   UPDATE wp_posts SET post_content = REPLACE(post_content, '2026.abakus.cz', 'abakus.cz');
   UPDATE wp_posts SET guid = REPLACE(guid, '2026.abakus.cz', 'abakus.cz');
   UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '2026.abakus.cz', 'abakus.cz');
   UPDATE wp_options SET option_value = REPLACE(option_value, '2026.abakus.cz', 'abakus.cz');
   "
   ```
6. Regenerate Elementor CSS:
   ```bash
   cd /var/www/wordpress && sudo -u www-data wp eval '
   $posts = array(6, 43, 59, 926);
   foreach($posts as $id) { $css = new \Elementor\Core\Files\CSS\Post($id); $css->update(); }
   '
   ```
7. Clear caches:
   ```bash
   sudo -u www-data wp cache flush && sudo -u www-data wp transient delete --all
   sudo systemctl restart php8.3-fpm nginx
   ```
8. Test thoroughly on abakus.cz
9. Stop old Bitnami VM (wordpresspro-1-vm) after verification period

---

## Domain Configuration per Environment

### Staging (wp-abakus-2026)
- **nginx config**: `server_name 2026.abakus.cz;`
- **SSL certificate**: `/etc/letsencrypt/live/2026.abakus.cz/`
- **Database URLs**: All content URLs point to 2026.abakus.cz

### Test (wp-abakus-test)
- **nginx config**: `server_name test.abakus.cz;`
- **SSL certificate**: `/etc/letsencrypt/live/test.abakus.cz/`
- **Database URLs**: All content URLs point to test.abakus.cz

For production cutover, staging VM will be updated to use `abakus.cz`.

---

## Admin Security Recommendations

The old site had NO admin restriction at network level. Consider adding:

### Option 1: IP Whitelist in nginx
```nginx
location /wp-admin {
    allow 1.2.3.4;  # Office IP
    allow 5.6.7.8;  # VPN IP
    deny all;
    try_files $uri $uri/ /index.php?$args;
}

location ~ ^/wp-login\.php {
    allow 1.2.3.4;
    allow 5.6.7.8;
    deny all;
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
}
```

### Option 2: GCP Firewall (more secure)
Create separate firewall rule for admin ports with source IP restrictions.

### Option 3: VPN/IAP
Use GCP Identity-Aware Proxy or require VPN connection for admin access.

---

## Useful Commands

### SSH to VMs
```bash
# Staging (2026.abakus.cz) - will become production
gcloud compute ssh wp-abakus-2026 --zone=europe-west1-b --project=abakus-web

# Test (test.abakus.cz)
gcloud compute ssh wp-abakus-test --zone=europe-west3-a --project=lab-fb-web

# Old Bitnami (current production - to be decommissioned)
gcloud compute ssh wordpresspro-1-vm --zone=europe-west4-b --project=abakus-web
```

### Regenerate Elementor CSS
```bash
cd /var/www/wordpress && sudo -u www-data wp eval '
$posts = array(6, 43, 59, 926);
foreach($posts as $id) {
    $post_css = new \Elementor\Core\Files\CSS\Post($id);
    $post_css->update();
}
'
```

### Update Database URLs (for production)
```bash
sudo mysql wordpress -e "
UPDATE wp_options SET option_value = 'https://abakus.cz' WHERE option_name IN ('siteurl', 'home');
UPDATE wp_posts SET post_content = REPLACE(post_content, 'test.abakus.cz', 'abakus.cz');
UPDATE wp_posts SET guid = REPLACE(guid, 'test.abakus.cz', 'abakus.cz');
UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, 'test.abakus.cz', 'abakus.cz');
UPDATE wp_options SET option_value = REPLACE(option_value, 'test.abakus.cz', 'abakus.cz');
"
```

### Clear All Caches
```bash
sudo -u www-data wp cache flush
sudo -u www-data wp transient delete --all
sudo rm -f /var/www/wordpress/wp-content/uploads/elementor/css/*.css
sudo systemctl restart php8.3-fpm nginx
```

---

## Hide My WP Nginx Configuration

The Hide My WP plugin requires nginx rewrite rules to function properly.

### Configuration File Location Differences

**Old Server (Bitnami):**
- Location: `/opt/bitnami/apps/wordpress/conf/nginx-app.conf`
- Single file containing all nginx app configuration

**New Server (Ubuntu 24.04):**
- Location: `/etc/nginx/snippets/hide-my-wp.conf`
- Modular approach following Ubuntu nginx conventions
- Included in main site config: `/etc/nginx/sites-available/wordpress`

### ⚠️ Migration Status: INCOMPLETE

The Hide My WP configuration was partially migrated but is **missing critical PHP file blocking rules**.

**What's Present ✅:**
- Login page obfuscation (`/prihlaseni` → `/wp-login.php`)
- wp-content, wp-includes, wp-admin path hiding
- Plugin and theme path obfuscation
- Cookie-based bypass mechanism (`eadcc=1`)

**What's Missing ⚠️:**
- **PHP file blocking rules** (security gap - allows direct PHP access)
- Plugin-specific rules for Duplicator and WP-Optimize (installed but inactive)

### /etc/nginx/snippets/hide-my-wp.conf
```nginx
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
rewrite ^/lib/js/embed\.min\.js /wp-includes/js/wp-embed.min.js?ca_pristup=skryt last;
rewrite ^/hello-elementor/(.*) /wp-content/themes/hello-elementor/$1?ca_pristup=skryt last;
rewrite ^/skin_main/style\.css /?parent_wrapper=1&ca_pristup=skryt last;
rewrite ^/skin_main/(.*) /wp-content/themes/hello-elementor/$1?ca_pristup=skryt last;
rewrite ^/prihlaseni /wp-login.php?ca_pristup=skryt last;
rewrite ^/lib/(.*) /wp-includes/$1?ca_pristup=skryt last;
rewrite ^/file/(.*) /wp-content/uploads/$1?ca_pristup=skryt last;
rewrite ^/ext/05e0390b/(.*) /wp-content/plugins/disable-comments/$1?ca_pristup=skryt last;
rewrite ^/ext/735ef6b6/(.*) /wp-content/plugins/bdthemes-element-pack/$1?ca_pristup=skryt last;
rewrite ^/ext/892610ac/(.*) /wp-content/plugins/cookie-law-info/$1?ca_pristup=skryt last;
rewrite ^/ext/82ab7f61/(.*) /wp-content/plugins/seo-by-rank-math/$1?ca_pristup=skryt last;
rewrite ^/ext/1b13f21e/(.*) /wp-content/plugins/wp-mail-smtp/$1?ca_pristup=skryt last;
rewrite ^/ext/f82f3375/(.*) /wp-content/plugins/duplicate-post/$1?ca_pristup=skryt last;
rewrite ^/ext/(.*) /wp-content/plugins/$1?ca_pristup=skryt last;
rewrite ^/skin/main\.css /?style_wrapper=1&ca_pristup=skryt last;
rewrite ^/skin/style\.css /nothing_404_404?ca_pristup=skryt last;
rewrite ^/skin/(.*) /wp-content/themes/hello-theme-child-master/$1?ca_pristup=skryt last;
rewrite ^/user_submit /wp-comments-post.php?ca_pristup=skryt last;
rewrite ^/ajax /wp-admin/admin-ajax.php?ca_pristup=skryt last;
rewrite ^/inc/(.*) /wp-content/$1?ca_pristup=skryt last;
rewrite ^/(readme\.html|license\.txt|wp-content/debug\.log|wp-includes/$) /nothing_404_404?ca_pristup=skryt last;
# END Hide My WP
```

### Missing PHP Blocking Rules (Security Gap)

These rules from the old server are **NOT** present in the new configuration:

```nginx
# Allow legitimate PHP files only
rewrite ^/(index\.php|wp-comments-post\.php|wp-includes/js/tinymce/wp-tinymce\.php|xmlrpc\.php|wp-cron\.php|wp-login\.php|index\.php|wp-admin/|prihlaseni)(.*) /$1$2?ca_pristup=skryt break;

# Block all other PHP files
rewrite ^/(.*)\.php(.*) /nothing_404_404?ca_pristup=skryt last;
```

**Security Impact:** Without these rules, direct PHP file access may bypass Hide My WP protection.

**To Fix:** Add these rules to `/etc/nginx/snippets/hide-my-wp.conf` before the `# END Hide My WP` line, then reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### Missing Plugin-Specific Rules

The old server had these plugin rules that are not on the new server:

```nginx
# Duplicator plugin (installed but inactive)
rewrite ^/ext/219d8031/(.*) /wp-content/plugins/duplicator/$1?ca_pristup=skryt last;

# WP-Optimize plugin (installed but inactive)
rewrite ^/ext/6e235b43/(.*) /wp-content/plugins/wp-optimize/$1?ca_pristup=skryt last;

# RevSlider CSS (plugin not installed - can be ignored)
rewrite ^/ext/231436b4/public/assets/css/settings\.css /wp-content/plugins/revslider/public/assets/css/settings.css?ca_pristup=skryt last;
```

These are only needed if the plugins are activated and use obfuscated paths.

### Include in /etc/nginx/sites-available/wordpress
Already included inside the server block (line ~130):
```nginx
# Include Hide My WP rules
include /etc/nginx/snippets/hide-my-wp.conf;
```

### Path Mappings
| Public URL | Internal Path |
|------------|---------------|
| `/prihlaseni` | `/wp-login.php` |
| `/ext/` | `/wp-content/plugins/` |
| `/lib/` | `/wp-includes/` |
| `/file/` | `/wp-content/uploads/` |
| `/skin/` | `/wp-content/themes/hello-theme-child-master/` |
| `/ajax` | `/wp-admin/admin-ajax.php` |

---

## Fail2ban Brute Force Protection

Fail2ban is installed and configured to protect against brute force attacks.

### Configuration: /etc/fail2ban/jail.local
```ini
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
```

### WordPress Filter: /etc/fail2ban/filter.d/wordpress.conf
```ini
[Definition]
failregex = ^<HOST> .* "POST .*(wp-login\.php|prihlaseni).* HTTP/.*" (200|403) .*$
ignoreregex =
```

### Useful Commands
```bash
# Check fail2ban status
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status sshd
sudo fail2ban-client status wordpress

# Unban an IP
sudo fail2ban-client set sshd unbanip 1.2.3.4
sudo fail2ban-client set wordpress unbanip 1.2.3.4

# View banned IPs
sudo fail2ban-client status wordpress | grep "Banned IP"

# View fail2ban log
sudo tail -f /var/log/fail2ban.log
```

---

## Additional Security Hardening

### XML-RPC Disabled
XML-RPC is blocked at nginx level to prevent DDoS amplification and brute force attacks.

**Config:** `/etc/nginx/snippets/security-xmlrpc.conf`
```nginx
location = /xmlrpc.php {
    deny all;
    access_log off;
    log_not_found off;
    return 444;
}
```

### Automatic Security Updates
Unattended-upgrades is configured to automatically install security patches.

**Config:** `/etc/apt/apt.conf.d/50unattended-upgrades`
- Security updates: Enabled
- Automatic reboot: Disabled (manual control)
- Unused packages cleanup: Enabled

```bash
# Check unattended-upgrades status
sudo systemctl status unattended-upgrades

# View upgrade log
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log

# Manually run updates
sudo unattended-upgrade --dry-run  # test
sudo unattended-upgrade            # apply
```

### SSH Hardened (Key-Only Authentication)
Password authentication is disabled. Only SSH key-based login is allowed.

**Config:** `/etc/ssh/sshd_config`
```
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
```

### GCP Firewall (Open Ports)
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | 0.0.0.0/0 | SSH (key-only) |
| 80 | TCP | 0.0.0.0/0 | HTTP → HTTPS |
| 443 | TCP | 0.0.0.0/0 | HTTPS |
| ICMP | - | 0.0.0.0/0 | Ping |

RDP (3389) has been removed.

### SSH Users
| User | SSH Key | Purpose |
|------|---------|---------|
| vaclav.rak | vaclav.rak@LINX-000112, rak@avast.com | Main admin |
| Abakus | Abakus@Transmit | Legacy access (Transmit app) |

SSH keys are provisioned via Terraform instance metadata.

---

## Monitoring & Alerts

GCP Uptime Checks monitor site availability and SSL certificate validity.

### Uptime Checks
| Check | Endpoint | Interval | SSL Validation |
|-------|----------|----------|----------------|
| WordPress HTTPS | /health | 60s | Yes |
| SSL Certificate | / | 15min | Yes |

### Alert Policy
- **Condition:** Site unreachable for 5 minutes
- **Notification:** Email to rak@webeye.services
- **Auto-close:** 7 days after recovery

### Health Endpoint
nginx snippet: `/etc/nginx/snippets/health-check.conf`
```nginx
location = /health {
    access_log off;
    add_header Content-Type text/plain;
    return 200 "OK";
}
```

### View in GCP Console
- [Uptime Checks - lab-fb-web](https://console.cloud.google.com/monitoring/uptime?project=lab-fb-web)
- [Uptime Checks - abakus-web](https://console.cloud.google.com/monitoring/uptime?project=abakus-web)
- [Alerting Policies - lab-fb-web](https://console.cloud.google.com/monitoring/alerting?project=lab-fb-web)
- [Alerting Policies - abakus-web](https://console.cloud.google.com/monitoring/alerting?project=abakus-web)
