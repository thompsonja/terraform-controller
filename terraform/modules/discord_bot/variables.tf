variable "bot_name" {
  description = "Name of the discord bot"
  type        = string
}

variable "github_trigger" {
  type = object({
    branch          = string
    included_files  = list(string)
    repo_owner      = string
    repo_name       = string
    cloudbuild_file = string
  })
  description = <<EOT
    github_trigger = {
      branch: "Branch to use to trigger builds"
      included_files: "Optional regex glob of files to use to trigger builds"
      repo_owner: "GitHub repository owner to use to trigger builds"
      repo_name: "GitHub repository name to use to trigger builds"
      cloudbuild_file: "GCP Cloud Build config file"
    }
  EOT
}

variable "gcp" {
  type = object({
    additional_roles       = list(string)
    additional_secrets     = list(string)
    artifact_repository_id = string
    notification_channels  = list(string)
    owner                  = string
    project_id             = string
    project_number         = string
    zone                   = string
  })
  description = <<EOT
    gcp = {
      additional_roles:       = "Additional GCP roles to generate for this bot"
      additional_secrets:     = "Additional GCP Cloud Secrets to generate for this bot"
      artifact_repository_id: = "GCP Artifact Registry Repository ID"
      notification_channels: = "List of GCP monitoring notification channel IDs"
      owner: "Owner to grant build/deploy access to"
      project_id: "GCP Project ID"
      project_number: "GCP Project Number"
      zone: "GCP Zone to deploy bot resource to"
    }
  EOT
}
