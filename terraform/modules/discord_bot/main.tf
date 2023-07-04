// Create a new Service Account. This is needed so that each Discord bot has a
// separate identity to act as, allowing us to separate access to different
// parts of our cloud infrastructure.
resource "google_service_account" "bot-service-account" {
  project      = var.gcp.project_id
  account_id   = "${var.bot_name}-sa"
  display_name = "Service Account for ${var.bot_name} discord bot"
}

// Grant yourself and the Cloud Build service account the ability to act as the
// bot Service Account. This is needed for deploying bots.
resource "google_service_account_iam_binding" "bot-iam-binding" {
  service_account_id = google_service_account.bot-service-account.name
  role               = "roles/iam.serviceAccountUser"

  members = [
    "serviceAccount:${var.gcp.project_number}@cloudbuild.gserviceaccount.com",
    "user:${var.gcp.owner}"
  ]
}

// Grant the bot Service Account the ability to write logs, in addition to any
// specified as a var.
resource "google_project_iam_member" "bot-role" {
  for_each = toset(concat(var.gcp.additional_roles, ["roles/logging.logWriter"]))
  project  = var.gcp.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.bot-service-account.email}"
}

// Every bot gets at least a single secret created to store the Discord bot key
// generated when you create a new bot.
resource "google_secret_manager_secret" "bot-key" {
  project   = var.gcp.project_id
  secret_id = "${var.bot_name}-key"

  replication {
    user_managed {
      replicas {
        location = var.gcp.zone
      }
    }
  }
}

// Create any additional secrets specified as a var.
resource "google_secret_manager_secret" "bot-secrets" {
  for_each  = toset(var.gcp.additional_secrets)
  project   = var.gcp.project_id
  secret_id = each.key

  replication {
    user_managed {
      replicas {
        location = var.gcp.zone
      }
    }
  }
}

// Make sure you and the bot can access these secrets.
resource "google_secret_manager_secret_iam_binding" "bot-secrets-access" {
  for_each  = merge({ "bot-key" = google_secret_manager_secret.bot-key }, google_secret_manager_secret.bot-secrets)
  project   = var.gcp.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_service_account.bot-service-account.email}",
    "user:${var.gcp.owner}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "bot-secrets-viewer" {
  for_each  = merge({ "bot-key" = google_secret_manager_secret.bot-key }, google_secret_manager_secret.bot-secrets)
  project   = var.gcp.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.viewer"
  members = [
    "serviceAccount:${google_service_account.bot-service-account.email}",
    "user:${var.gcp.owner}"
  ]
}

// This lets you be able to update the secret when you obtain it from Discord.
resource "google_secret_manager_secret_iam_binding" "bot-secrets-writer" {
  for_each  = merge({ "bot-key" = google_secret_manager_secret.bot-key }, google_secret_manager_secret.bot-secrets)
  project   = var.gcp.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretVersionManager"
  members = [
    "user:${var.gcp.owner}"
  ]
}

// Define a Cloud Run service
resource "google_cloud_run_service" "service" {
  name     = var.bot_name
  location = var.gcp.zone
  project  = var.gcp.project_id

  template {
    spec {
      containers {
        image   = "us-docker.pkg.dev/cloudrun/container/hello:latest"
        command = ["/server"]
        args    = ["--project_id=${var.gcp.project_id}"]
      }
      service_account_name = google_service_account.bot-service-account.email
    }
    metadata {
      annotations = {
        // For simplicity, I'm scaling from 0 to 1, if you anticipate more
        // traffic you will want to update this and make it a variable.
        "autoscaling.knative.dev/minScale" = "0",
        "autoscaling.knative.dev/maxScale" = "1"
      }
    }
  }
  autogenerate_revision_name = true

  traffic {
    percent         = 100
    latest_revision = true
  }
}

// This allows us to make the service public facing, necessary for Discord bots.
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.service.location
  project  = google_cloud_run_service.service.project
  service  = google_cloud_run_service.service.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

// Create a Cloud Build trigger that fires when the GitHub repo is updated.
resource "google_cloudbuild_trigger" "service-trigger" {
  // Make location global in order to avoid any quota issues with a zone
  location = "global"
  project  = google_cloud_run_service.service.project
  name     = "${google_cloud_run_service.service.name}-trigger"

  included_files = var.github_trigger.included_files != null ? var.github_trigger.included_files : []

  github {
    owner = var.github_trigger.repo_owner
    name  = var.github_trigger.repo_name
    push {
      branch = var.github_trigger.branch
    }
  }

  substitutions = {
    _APP         = var.bot_name
    _ZONE        = var.gcp.zone
  }

  filename = var.github_trigger.cloudbuild_file

  include_build_logs = "INCLUDE_BUILD_LOGS_WITH_STATUS"
}

// Create a GCP logging metric to count errors
resource "google_logging_metric" "error_logging_metric" {
  name        = "${var.bot_name}_errors"
  project     = var.gcp.project_id
  filter      = "severity >= ERROR AND logName=\"projects/${var.gcp.project_id}/logs/${var.bot_name}-logs\""
  description = "Logged errors for ${var.bot_name} bot"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

// Monitor the logging metric and send emails whenever this alert fires.
resource "google_monitoring_alert_policy" "error_logging_alert_policy" {
  display_name = "${var.bot_name} Error Alert"
  project      = var.gcp.project_id
  combiner     = "OR"
  conditions {
    display_name = "Error logs"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${var.bot_name}_errors\" AND resource.type=\"cloud_run_revision\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.5
      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = var.gcp.notification_channels != null ? var.gcp.notification_channels : []
  alert_strategy {
    auto_close = "3600s"
  }
}
