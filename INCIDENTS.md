# Incident Log

## 2026-10-24 — Static assets 404 on abakus.cz (missing nginx rewrites + cache)

### Symptom
The homepage HTML rendered, but every static asset 404'd: fonts
(`sourcesanspro-*.woff2`, `sourceserifpro-*.woff2`), theme CSS (`reset.css`,
`theme.css`, `header-footer.css`), and all Elementor widget CSS/JS
(`frontend.min.css`, `widget-image.min.css`, `sticky.min.css`, …). The site
looked completely unstyled.

### Root Cause
Same **2026-10-22 08:17 UTC reboot** as the TLS incident below. The startup
script re-ran and rewrote `/etc/nginx/sites-available/wordpress` with its bare
template, which:
- left the Hide My WP include **commented out**
  (`# include /etc/nginx/snippets/hide-my-wp.conf;  # Enable after …`), so the
  `/ext/` → `wp-content/plugins`, `/lib/` → `wp-includes`, `/skin/` → theme
  rewrites were gone and every obfuscated asset URL 404'd;
- dropped the **entire FastCGI page cache** (the June-outage mitigation), the
  `2026.abakus.cz` server block, HSTS/`X-Cache-Status` headers and
  `stub-status.conf`.

The 08:33 immediate fix that day restored only the Let's Encrypt cert line, not
the rest, so the site served unstyled from 2026-10-22 until this fix on
2026-10-24.

### Immediate Fix (two parts)
1. **Vhost.** Restored the known-good pre-reboot vhost from
   `/root/config-backups/wordpress.bak-20260901-064009` (backed the clobbered
   one up to `/root/config-backups/wordpress.pre-restore.<ts>` first),
   `nginx -t`, reload. This re-enabled the HMW include, the FastCGI cache, the
   `2026.abakus.cz` block and the headers.
2. **HMW snippet.** The restored vhost re-enabled the include, but the *snippet*
   on disk (`/etc/nginx/snippets/hide-my-wp.conf`) was still the generic version
   startup.sh regenerated at 08:21 — it had only `^/ext/(.*) → plugins/$1` and
   `^/skin/(.*) → child-theme`, and was **missing** the per-plugin hash rewrites
   and the `/skin_main/` (parent-theme) rules. So hashed-plugin and parent-theme
   assets still 404'd (`/ext/735ef6b6/…` element-pack, `/ext/f554c2ba/…` cookie
   consent, `/skin_main/…` reset/theme/header-footer.css, `/skin/main.css`).
   Installed the full ruleset from `scripts/hide-my-wp.conf` (backup saved to
   `/root/config-backups/hide-my-wp.conf.bak-<ts>`).

Note: the repo snippet's cookie-plugin rule was stale — it mapped
`892610ac → cookie-law-info`, but the site now uses `kansleri-cookie-consent`
(hashed `f554c2ba`), and `cookie-law-info` is no longer installed.
`scripts/hide-my-wp.conf` was updated to `f554c2ba → kansleri-cookie-consent`.

### Verification
Both `/` and `/kontakt/` sweep clean — every `href`/`src` asset AND every
`url(...)` font inside the CSS returns 200 (30/30 and 22/22). `X-Cache-Status`
flips MISS→HIT on a second hit, `/prihlaseni` 200, `wp-login.php` 404 (HMW
hardening, expected). Every URL from both reported console pastes resolves.

### Permanent Fix (recurrence prevention) — STILL OPEN
This is the **same clobber-on-reboot pattern** as the TLS incident. Note
`terraform-2026/main.tf:142` has `ignore_changes = [metadata_startup_script]`,
so editing `scripts/startup.sh` neither replaces the VM nor updates the
startup-script stored in instance metadata — **the next reboot will re-run the
old script and re-break everything (snakeoil cert, HMW include, cache).**
A real fix must either push a corrected script to instance metadata
(`gcloud compute instances add-metadata … startup-script=…`) or add a boot-time
unit that re-applies config after `google-startup-scripts`. `startup.sh` should
also be corrected in-repo so a rebuild is right.

## 2026-10-22 — TLS Certificate Untrusted on abakus.cz

### Symptom
Browsers reported an untrusted certificate for `https://abakus.cz/`. nginx was
serving the self-signed **snakeoil** cert (`CN=wp-abakus-2026…internal`, a
10-year self-signed cert) instead of the valid Let's Encrypt cert, which existed
and was current on disk the whole time (`/etc/letsencrypt/live/abakus.cz/`,
valid through 2026-12-20, covering `abakus.cz` + `www.abakus.cz`).

### Root Cause
The `wp-abakus-2026` VM **rebooted at 08:17 UTC**. GCP re-runs the metadata
startup script on *every* boot, so `scripts/startup.sh` ran again (finished
08:21) and **unconditionally rewrote** `/etc/nginx/sites-available/wordpress`
with a hardcoded snakeoil placeholder in the 443 block:
```
ssl_certificate     /etc/ssl/certs/ssl-cert-snakeoil.pem;
ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
```
The real Let's Encrypt cert was only ever wired in by the one-time manual
`certbot --nginx` step in `cutover-to-production.sh`, which did not run on this
boot, and certbot's auto-renewal was not due (59 days left). Result: nginx
reloaded with the placeholder. This is a **recurrence** of the snakeoil issue
first fixed on 2026-06-16 — that fix corrected the live config but not the
startup script, so the next reboot re-introduced it.

### Immediate Fix
Re-pointed the vhost at the Let's Encrypt cert and reloaded nginx (backup saved
as `wordpress.bak.<timestamp>`):
```
ssl_certificate     /etc/letsencrypt/live/abakus.cz/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/abakus.cz/privkey.pem;
```
Verified: `curl` reports `ssl_verify=0`, HTTP 200 on apex, www→non-www 301.

### Permanent Fix
`scripts/startup.sh` no longer uses snakeoil at all. The HTTPS server block is
now emitted **only when a real Let's Encrypt cert exists** for `$DOMAIN`, with
`ssl_certificate` pointing straight at `/etc/letsencrypt/live/$DOMAIN/`. On
first boot (no cert) nginx serves HTTP only so `certbot --nginx` can obtain the
cert and add the 443 block; on every later reboot the full HTTPS block is
regenerated against the real cert. No self-signed cert is ever served.
- **Not yet deployed**: editing `startup.sh` triggers a full VM replacement on
  `terraform apply`, so the change lives in the repo and must be rolled out
  deliberately. The live VM already carries the corrected config from the
  immediate fix above.

## 2026-06-16 — Production Outage (7:00–8:00, 10:00–12:00 UTC)

### Root Causes

**1. Insufficient server capacity**
The `wp-abakus-2026` instance was running on `e2-small`, which could not handle real production traffic. PHP-FPM workers were consuming 23–27% CPU each (5 workers) on a single shared vCPU.
- Fix: instance upgraded to `e2-medium` (2 vCPU, 4 GB RAM).

**2. Monitoring pointed at dev instance**
Uptime monitoring was configured during migration and was watching the dev environment, not production. No alerts were triggered.
- Fix: monitoring redirected to `abakus.cz`, VM health alerts added (CPU, memory, disk).

**3. Notification channel misconfigured**
Alerts did not arrive in time because the monitoring channel was wired to the wrong instance.
- Fix: notification channels verified and reconnected to production.

### Changes Made

- `e2-small` → `e2-medium`
- FastCGI page cache enabled (nginx) — anonymous visitors are served cached HTML, bypassing PHP and MariaDB entirely
- GCP Monitoring dashboard created (CPU, memory, disk, nginx requests, network, uptime)
- VM health alert policies added to Terraform (CPU > 80%, memory > 85%, disk > 85%)
- SSL certificates fixed — nginx was using snakeoil placeholder instead of Let's Encrypt certs
- Nginx rewrite for `/ext/` paths (Elementor assets) was uncommented and re-enabled

### Recommendations

- **CDN proxy** (e.g. Cloudflare) — the site becomes effectively static for visitors; PHP is only invoked on content updates. Eliminates overload risk during traffic spikes and would have prevented this outage.
- **Static site export** — generate HTML from WordPress and host without PHP entirely.
- WordPress + PHP is overkill for a largely static website.
