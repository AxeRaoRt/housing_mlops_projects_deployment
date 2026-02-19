terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Stocker le state dans GCS (Google Cloud Storage)
  backend "gcs" {
    bucket = "bucket-mlops-junia"
    prefix = "prod/terraform.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Instance Compute Engine
resource "google_compute_instance" "app" {
  name         = "app-server-vm"
  machine_type = "e2-standard-4"  # free tier eligible
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10  # GB
    }
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.public.id

    # IP publique
    access_config {}
  }

    metadata = {
    # image_name= "europe-west1-docker.pkg.dev/${var.project_id}/${var.repository}/fraud-${var.service_name}"
    # On passe le tag de l'image via les metadata
    image_tag = var.app_image_tag
    image_repository = var.repository
    project_id = var.project_id
    # Le script qui s'exécute au boot et à chaque changement de metadata
    startup-script = file("${path.module}/scripts/deploy.sh")
    }

  tags = ["http-server", "https-server", "ssh-server"]

  service_account {
    email  = google_service_account.app.email
    scopes = ["cloud-platform"]
  }
}

# Service Account pour l'instance
resource "google_service_account" "app" {
  account_id   = "app-server-sa"
  display_name = "App Server Service Account"
}

# On donne le rôle de lecteur au Service Account de la VM
resource "google_project_iam_member" "reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:app-server-sa@${var.project_id}.iam.gserviceaccount.com"
}