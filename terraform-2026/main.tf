# --- WordPress Production VM Infrastructure ---
# Project: abakus-web
# Domain: abakus.cz (production)
# WARNING: This config MUST NOT touch wordpresspro-1-vm (old Bitnami VM)

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file("${path.module}/../.secrets/wp-2026-deployer.json")
}

variable "project_id" {
  description = "GCP Project ID"
  default     = "abakus-web"
}

variable "region" {
  description = "GCP Region"
  default     = "europe-west1"  # Belgium - cheapest in Europe
}

variable "zone" {
  description = "GCP Zone"
  default     = "europe-west1-b"
}

variable "domain" {
  description = "Domain for the WordPress site"
  default     = "abakus.cz"
}

variable "production_domain" {
  description = "Future production domain"
  default     = "abakus.cz"
}

variable "vm_name" {
  description = "Name of the VM instance"
  default     = "wp-abakus-2026"
}

variable "env" {
  description = "Environment"
  default     = "production"
}

variable "alert_email" {
  description = "Email for monitoring alerts"
  default     = "rak@webeye.services"
}

variable "alert_sms" {
  description = "Phone number for SMS alerts (E.164 format)"
  default     = "+420608878558"
}

# ===========================================
# NETWORK
# ===========================================

# Static external IP
resource "google_compute_address" "wordpress_ip" {
  name   = "wp-abakus-2026-ip"
  region = var.region
}

# Firewall rules - using unique names to avoid conflict
resource "google_compute_firewall" "wordpress_http" {
  name    = "wp-abakus-2026-allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["wp-abakus-2026"]
}

resource "google_compute_firewall" "wordpress_ssh_ipv4" {
  name    = "wp-abakus-2026-allow-ssh-ipv4"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["89.248.248.178/32"]
  target_tags   = ["wp-abakus-2026"]
}

resource "google_compute_firewall" "wordpress_ssh_ipv6" {
  name    = "wp-abakus-2026-allow-ssh-ipv6"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["2a01:168:3118:150::/64"]
  target_tags   = ["wp-abakus-2026"]
}

# ===========================================
# VM INSTANCE
# ===========================================

resource "google_compute_instance" "wordpress" {
  name         = var.vm_name
  machine_type = "e2-medium"
  zone         = var.zone

  tags = ["wp-abakus-2026"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.wordpress_ip.address
    }
  }

  metadata = {
    domain            = var.domain
    production_domain = var.production_domain
    ssh-keys          = <<-EOT
      Abakus:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDTR51UZBsUAhB/++pcvOi2BtEjTCBhy1JAjNfv3eTChzD1z4jDHB6aA3U4JMySBfZVxBE4XYPxWZc8TpG3NBytWeRbxVnxi2dIbMPpqqKJyneB1iE+qswu7XfIsu6KLDLKYHJ+a2RMV9/A+3GOigam7P8CIWnPLrt58eCymgmxl/ZLccxieasGM5a802qvggHd6kaaTp0oURTQv0fF3BNanfYX+mkD80CeeX6/aKPAZu6UJUdZGWd3GnDLs9XVkPJjuAMJdYuOpaLe2hAcWWeckRvlu67o+ZEoGS2DhtaywfjkHdOsvVd3wNc6MLRC8TVIwxpGccjyQq4SmEqadd6F Abakus@Transmit
      vaclav.rak:ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAg0IsU+W308OTCIlZHteBmgSfQj+UqrigmfBOVKKCHJ76xMCfLt1Yi9Jt1VBZ4YPVaNBKqDzCJGTGACvQLf8UcSTMW7kNZ+wpg9FG3FA3TSL91HqKCIrfR0Ksd+45uhhhRYNycwP9l7AJE90VGIlTfKsYHBR7EC9CyLbv1h9M8vLBvWg177mrMGyJ3wu6fF/PAP1vs7uYGOzWSQxrmQlhOK4PEVbt+3yD4xYW2LF2XfDRRRY+og/Arm9J1KTTez1OacVnYgCPFb10e+scw03vm718YfdLaKEbyWLh8ZgCpITBgvVtoFLqZj4/319NeKQLBt3AGfHLzV1iwYCj3vANJCDrDgbtXCSJ1Ruood3C/KyrsOYJGx73imU4aV9qBtaWArr6EU/YO7q/bCVJJOV/0m3Zzj7lj0lunrvFHfroVTHfQdjuzNmoBi0AZlj+t7wubB+dywQ5aAonK7T2pVbXbVFEgI3bP+K6tYO65sARLyAl1hjXkpd13hv2m40mu0SACAvxJWMiY9m1AXSrMTjGT2z8dMsQ8qme+puoytsZfvcx+Ku7umV7OvZSs2kGqkmuFwdJ/B1LCfer6hj3mws0aOhFh5VmyI4GPrDdT961f3iQPsYYvDxUEgZb6x+miUM4hCgRTb02+vySknXJkTae4/0PJseCDj3zN/tqrGRSxEZNKNDbnCK92wPlvwfVO0= rak@avast.com
    EOT
  }

  metadata_startup_script = file("${path.module}/../scripts/startup.sh")

  service_account {
    scopes = ["cloud-platform"]
  }

  labels = {
    app = "wordpress"
    env = var.env
  }
}

# ===========================================
# BACKUP - SNAPSHOT SCHEDULES
# ===========================================

resource "google_compute_resource_policy" "daily_backup" {
  name    = "wp-abakus-2026-daily-backup"
  region  = var.region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "03:00"
      }
    }

    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = {
        app    = "wordpress"
        env    = var.env
        backup = "daily"
      }
      storage_locations = [var.region]
    }
  }
}

resource "google_compute_resource_policy" "weekly_backup" {
  name    = "wp-abakus-2026-weekly-backup"
  region  = var.region
  project = var.project_id

  snapshot_schedule_policy {
    schedule {
      weekly_schedule {
        day_of_weeks {
          day        = "SUNDAY"
          start_time = "04:00"
        }
      }
    }

    retention_policy {
      max_retention_days    = 30
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels = {
        app    = "wordpress"
        env    = var.env
        backup = "weekly"
      }
      storage_locations = [var.region]
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "daily" {
  name    = google_compute_resource_policy.daily_backup.name
  disk    = var.vm_name
  zone    = var.zone
  project = var.project_id
}

resource "google_compute_disk_resource_policy_attachment" "weekly" {
  name    = google_compute_resource_policy.weekly_backup.name
  disk    = var.vm_name
  zone    = var.zone
  project = var.project_id
}

# ===========================================
# MONITORING & ALERTS
# ===========================================

resource "google_monitoring_notification_channel" "slack" {
  display_name = "GCP Abakus monitoring"
  type         = "slack"
  project      = var.project_id

  labels = {
    channel_name = "#monitoring"
  }

  lifecycle {
    ignore_changes = [labels]
  }
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "WordPress Production Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_notification_channel" "sms" {
  display_name = "WordPress Production SMS"
  type         = "sms"
  project      = var.project_id

  labels = {
    number = var.alert_sms
  }
}

resource "google_monitoring_uptime_check_config" "https" {
  display_name = "WordPress HTTPS - ${var.domain}"
  project      = var.project_id
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.domain
    }
  }
}

resource "google_monitoring_uptime_check_config" "ssl_cert" {
  display_name = "SSL Certificate - ${var.domain}"
  project      = var.project_id
  timeout      = "10s"
  period       = "900s"

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.domain
    }
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  display_name = "WordPress Down - ${var.domain}"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failing"

    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id = \"${google_monitoring_uptime_check_config.https.uptime_check_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.sms.id,
    google_monitoring_notification_channel.email.id,
    google_monitoring_notification_channel.slack.id,
  ]

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "ssl_cert" {
  display_name = "SSL Certificate Failing - ${var.domain}"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "SSL cert check failing"

    condition_threshold {
      filter          = "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id = \"${google_monitoring_uptime_check_config.ssl_cert.uptime_check_id}\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.sms.id,
    google_monitoring_notification_channel.email.id,
    google_monitoring_notification_channel.slack.id,
  ]

  alert_strategy {
    auto_close = "604800s"
  }
}

# ===========================================
# VM HEALTH MONITORING
# ===========================================

resource "google_monitoring_alert_policy" "cpu_high" {
  display_name = "VM CPU High - ${var.vm_name}"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "CPU utilization > 80% for 5 min"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.wordpress.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.id,
    google_monitoring_notification_channel.slack.id,
  ]

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "memory_high" {
  display_name = "VM Memory High - ${var.vm_name}"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Memory utilization > 85% for 5 min"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.wordpress.instance_id}\" AND metric.type = \"agent.googleapis.com/memory/percent_used\" AND metric.labels.state = \"used\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 85

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email.id,
    google_monitoring_notification_channel.slack.id,
  ]

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "disk_high" {
  display_name = "VM Disk Full - ${var.vm_name}"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Disk utilization > 85%"

    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.labels.instance_id = \"${google_compute_instance.wordpress.instance_id}\" AND metric.type = \"agent.googleapis.com/disk/percent_used\" AND metric.labels.state = \"used\" AND metric.labels.device = \"/dev/root\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 85

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.sms.id,
    google_monitoring_notification_channel.email.id,
    google_monitoring_notification_channel.slack.id,
  ]

  alert_strategy {
    auto_close = "604800s"
  }
}

# ===========================================
# MONITORING DASHBOARD
# ===========================================

resource "google_monitoring_dashboard" "wordpress" {
  project        = var.project_id
  dashboard_json = file("${path.module}/dashboard.json")
}

# ===========================================
# OPS AGENT INSTALLATION (via SSH)
# ===========================================

resource "null_resource" "ops_agent_install" {
  # Only run after VM is created
  depends_on = [google_compute_instance.wordpress]

  # Re-run if VM is recreated
  triggers = {
    instance_id = google_compute_instance.wordpress.instance_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Activate service account
      gcloud auth activate-service-account --key-file=${path.module}/../.secrets/wp-2026-deployer.json

      # Install Ops Agent via SSH
      gcloud compute ssh ${var.vm_name} --zone=${var.zone} --project=${var.project_id} --command='
        # Install Ops Agent
        curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
        sudo bash add-google-cloud-ops-agent-repo.sh --also-install

        # Create config directory if not exists
        sudo mkdir -p /etc/google-cloud-ops-agent

        # Create Ops Agent config
        sudo tee /etc/google-cloud-ops-agent/config.yaml > /dev/null << EOF
metrics:
  receivers:
    nginx:
      type: nginx
      stub_status_url: http://127.0.0.1/nginx_status
  service:
    pipelines:
      nginx:
        receivers: [nginx]

logging:
  receivers:
    nginx_access:
      type: nginx_access
      include_paths: [/var/log/nginx/wordpress.access.log]
    nginx_error:
      type: nginx_error
      include_paths: [/var/log/nginx/wordpress.error.log]
    syslog:
      type: files
      include_paths: [/var/log/syslog]
    fail2ban:
      type: files
      include_paths: [/var/log/fail2ban.log]
  service:
    pipelines:
      nginx:
        receivers: [nginx_access, nginx_error]
      system:
        receivers: [syslog, fail2ban]
EOF

        # Create nginx stub_status snippet
        sudo tee /etc/nginx/snippets/stub-status.conf > /dev/null << EOF
location /nginx_status {
    stub_status on;
    allow 127.0.0.1;
    deny all;
}
EOF

        # Add stub_status include to nginx config if not present
        if ! grep -q "stub-status.conf" /etc/nginx/sites-available/wordpress; then
          sudo sed -i "/health-check.conf/a\\    include /etc/nginx/snippets/stub-status.conf;" /etc/nginx/sites-available/wordpress
        fi

        # Test and reload nginx
        sudo nginx -t && sudo systemctl reload nginx

        # Restart Ops Agent
        sudo systemctl restart google-cloud-ops-agent
        sudo systemctl enable google-cloud-ops-agent

        # Configure log rotation for WordPress nginx logs
        sudo tee /etc/logrotate.d/wordpress-nginx > /dev/null << EOF
/var/log/nginx/wordpress.*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 \$(cat /var/run/nginx.pid)
    endscript
}
EOF

        # Test logrotate config
        sudo logrotate -d /etc/logrotate.d/wordpress-nginx 2>&1 | head -5

        echo "Ops Agent and log rotation configured successfully"
      '
    EOT
  }
}

# ===========================================
# OUTPUTS
# ===========================================

output "vm_external_ip" {
  value       = google_compute_address.wordpress_ip.address
  description = "External IP of the WordPress VM"
}

output "ssh_command" {
  value       = "gcloud compute ssh ${var.vm_name} --zone=${var.zone} --project=${var.project_id}"
  description = "SSH command to connect to the VM"
}

output "website_url" {
  value       = "https://${var.domain}"
  description = "Website URL"
}

output "dns_record" {
  value       = "Create A record: ${var.domain} -> ${google_compute_address.wordpress_ip.address}"
  description = "DNS configuration needed"
}

output "monitoring_dashboard" {
  value       = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
  description = "GCP Monitoring Dashboard"
}

output "dashboard_id" {
  value       = google_monitoring_dashboard.wordpress.id
  description = "Monitoring dashboard resource ID"
}
