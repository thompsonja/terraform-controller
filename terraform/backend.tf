terraform {
  backend "gcs" {
    bucket = "thompsonja-tf-controller"
    prefix = "discord-bots/terraform/state"
  }
}
