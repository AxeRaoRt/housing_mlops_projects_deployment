variable "project_id"          { type = string }
variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}
# variable "ssh_public_key_path" { type = string }

variable "app_image_tag" {
  type    = string
  default = "latest"
}

variable "repository" {
  type    = string
  default = "mlops-depots"
}


# docker pull europe-west1-docker.pkg.dev/mlops-projects-487817/mlops-depots/fraud-api:latest