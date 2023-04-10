resource "random_id" "id" {
  byte_length = 4
  prefix      = var.project_name
}

resource "google_project" "project" {
  name            = var.project_name
  project_id      = random_id.id.hex
  billing_account = var.billing_account
  org_id          = var.org_id
}

resource "google_project_service" "service" {
  provider = google-beta

  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "containerregistry.googleapis.com",
    "compute.googleapis.com",
    "firebase.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com"
  ])

  service = each.key

  project            = google_project.project.project_id
  disable_on_destroy = false
}

resource "time_sleep" "artifact_registry_api_enabling" {
  depends_on = [
    google_project_service.service["artifactregistry.googleapis.com"]
  ]

  create_duration = "2m"
}

resource "google_artifact_registry_repository" "artifact-repo" {
  provider      = google-beta
  location      = var.zone
  project       = google_project.project.project_id
  repository_id = "services"
  description   = "Docker images for services"
  format        = "DOCKER"

  depends_on = [
    time_sleep.artifact_registry_api_enabling
  ]
}

// Add roles for yourself. Viewer is fine, add others as appropriate.
// Update the email address
resource "google_project_iam_member" "joshua_thompsonja_roles" {
  for_each = toset([
    "roles/viewer"
  ])
  project = google_project.project.project_id
  role    = each.key
  member  = "user:joshua@thompsonja.com"
}

// Allow the Cloud Run Service Agent to access the Artifact Registry.
resource "google_project_iam_member" "serverless_robot_prod_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/run.serviceAgent"
  ])
  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:service-${google_project.project.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

// Grant Cloud Run Admin and Builder roles to the Cloud Build service account.
// This is needed to build new releases and deploy them to Cloud Run.
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/run.admin"
  ])
  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_project.project.number}@cloudbuild.gserviceaccount.com"
}

// Give the default compute service account the Cloud Run Admin role.
// This is needed for deploying Cloud Run services. 
resource "google_project_iam_member" "compute_roles" {
  for_each = toset([
    "roles/run.admin"
  ])
  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_project.project.number}-compute@developer.gserviceaccount.com"
}

// Allow Cloud Build to manage Cloud Run services
resource "google_project_iam_member" "gcp_sa_roles" {
  for_each = toset([
    "roles/cloudbuild.serviceAgent"
  ])
  project = google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:service-${google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

// Allow CloudBuild to act on behalf of another service account.
// This is needed to deploy services since each bot will use its own service account.
resource "google_service_account_iam_binding" "admin-account-iam" {
  service_account_id = "${google_project.project.id}/serviceAccounts/${google_project.project.number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"

  members = [
    "serviceAccount:${google_project.project.number}@cloudbuild.gserviceaccount.com",
  ]
}

// Needed to automate generating new Cloud Run revisions
resource "google_service_account_iam_binding" "run-service-agent" {
  service_account_id = "${google_project.project.id}/serviceAccounts/${google_project.project.number}-compute@developer.gserviceaccount.com"
  role               = "roles/run.serviceAgent"

  members = [
    "serviceAccount:service-${google_project.project.number}@serverless-robot-prod.iam.gserviceaccount.com",
  ]
}

// Create a bucket for Cloud Build
resource "google_storage_bucket" "cloud-build-bucket" {
  project       = google_project.project.project_id
  name          = "${google_project.project.project_id}_cloudbuild"
  location      = "US"
  force_destroy = true
}

// Create a new Secret to hold a GitHub key for automation.
// This is only needed if your repository is private.
resource "google_secret_manager_secret" "github-key" {
  project   = google_project.project.project_id
  secret_id = "github-private-repo-key"

  replication {
    user_managed {
      replicas {
        location = var.zone
      }
    }
  }
}

// Allow Cloud Build to access the GitHub key secret.
resource "google_secret_manager_secret_iam_binding" "github-access" {
  project   = google_project.project.project_id
  secret_id = google_secret_manager_secret.github-key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_project.project.number}@cloudbuild.gserviceaccount.com",
  ]
}

// Create a notification channel to be used by all bots.
// Replace the email address with your own.
resource "google_monitoring_notification_channel" "email-owner" {
  project      = google_project.project.project_id
  display_name = "Email Me"
  type         = "email"
  labels = {
    email_address = "joshua@thompsonja.com"
  }
}
