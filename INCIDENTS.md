# Incident Log

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
