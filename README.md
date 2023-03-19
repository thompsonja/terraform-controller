# terraform-controller
CI/CD infra project for Terraform.

## Project setup

Use `gcloud auth login` to login to the GCP user you wish to use to set up a
Terraform admin project and run `./admin_setup.sh`.

## Service Account

Once completed, the Terraform service account key will be located in
`${HOME}/.config/gcloud/<your_domain>-tf-controller.json`. It is recommended
that you copy its contents into a GitHub secret and then delete this file.
