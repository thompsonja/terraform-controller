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
