# VPC
resource "google_compute_network" "main" {
  name                    = "main-vpc"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "public" {
  name          = "public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.main.id
}

# Firewall — SSH
resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22", "8501", "5001", "3002", "9092", "8001"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}

# Firewall — HTTP/HTTPS
resource "google_compute_firewall" "web" {
  name    = "allow-web"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}