#!/bin/bash

set -euo pipefail

declare GCP_BILLING_ACCOUNT_ID=""
if [[ -z "${GCP_BILLING_ACCOUNT_ID}" ]]; then
  GCP_BILLING_ACCOUNT_ID="$(gcloud beta billing accounts list --format=json \
      | jq -r '.[0].name' \
      | cut -d'/' -f2)"
fi

declare GCP_ORGANIZATION_ID=""
if [[ -z "${GCP_ORGANIZATION_ID}" ]]; then
  GCP_ORGANIZATION_ID="$(gcloud organizations list --format=json \
      | jq -r '.[0].name' \
      | cut -d'/' -f2)"
fi


read -p "Enter a prefix for your GCP project (usually a domain name): " DOMAIN
TF_ADMIN="${DOMAIN}-tf-controller"
TF_CREDS="${HOME}/.config/gcloud/${TF_ADMIN}.json"

# Using an Admin Project for your Terraform service account keeps the resources
# needed for managing your projects separate from the actual projects you
# create.

# Create a new project and link it to your billing account:
echo "Creating GCP project ${TF_ADMIN}"
gcloud projects create ${TF_ADMIN} \
  --organization ${GCP_ORGANIZATION_ID} \
  --set-as-default

gcloud beta billing projects link ${TF_ADMIN} \
  --billing-account ${GCP_BILLING_ACCOUNT_ID}

# Create the service account in the Terraform admin project and download the
# JSON credentials:
echo "Creating service account"
gcloud iam service-accounts create terraform \
  --display-name "Terraform admin account"

gcloud iam service-accounts keys create ${TF_CREDS} \
  --iam-account terraform@${TF_ADMIN}.iam.gserviceaccount.com

# Grant the service account permission to view the Admin Project and manage
# Cloud Storage:
echo "Creating IAM bindings"
gcloud projects add-iam-policy-binding ${TF_ADMIN} \
  --member serviceAccount:terraform@${TF_ADMIN}.iam.gserviceaccount.com \
  --role roles/viewer

gcloud projects add-iam-policy-binding ${TF_ADMIN} \
  --member serviceAccount:terraform@${TF_ADMIN}.iam.gserviceaccount.com \
  --role roles/storage.admin

# Grant the service account permission to create projects and assign billing
# accounts:
gcloud organizations add-iam-policy-binding ${GCP_ORGANIZATION_ID} \
  --member serviceAccount:terraform@${TF_ADMIN}.iam.gserviceaccount.com \
  --role roles/resourcemanager.projectCreator

gcloud organizations add-iam-policy-binding ${GCP_ORGANIZATION_ID} \
  --member serviceAccount:terraform@${TF_ADMIN}.iam.gserviceaccount.com \
  --role roles/billing.user

# Create the remote backend bucket in Cloud Storage and the backend.tf file for
# storage of the terraform.tfstate file:
echo "Creating Terraform state bucket"
gsutil mb -p ${TF_ADMIN} gs://${TF_ADMIN}
gsutil versioning set on gs://${TF_ADMIN}

# Enable some sommon services. This allows Terraform to enable these services
# on projects it creates.
echo "Enabling GCP services"
gcloud services enable appengine.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable cloudbilling.googleapis.com
gcloud services enable firebase.googleapis.com
gcloud services enable firestore.googleapis.com
gcloud services enable iam.googleapis.com
