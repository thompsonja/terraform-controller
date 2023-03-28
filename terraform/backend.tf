terraform {
  backend "gcs" {
    bucket = "{{DOMAIN}}-tf-controller"
    prefix = "{{PROJECT_NAME}}/terraform/state"
  }
}
