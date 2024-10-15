terraform {
  backend "gcs" {
    bucket = "thompsonja-tf-controller"
    prefix = "testproject/terraform/state"
  }
}
