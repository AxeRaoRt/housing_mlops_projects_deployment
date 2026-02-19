#!/bin/bash
set -euo pipefail

LOG="/var/log/deploy.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Deploy started at $(date) ==="

# 1. Installation de Docker & Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Installation de Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ubuntu
fi

# 2. Attendre que Docker soit prêt
sleep 5
echo "Attente de Docker..."
until sudo docker info &> /dev/null; do
    sleep 2
done

# 3. Récupération des metadata
METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
H="Metadata-Flavor: Google"

VERSION=$(curl -sf -H "$H" "$METADATA_URL/instance/attributes/image_tag")
GAR_REPOSITORY=$(curl -sf -H "$H" "$METADATA_URL/instance/attributes/image_repository")
PROJECT_ID=$(curl -sf -H "$H" "$METADATA_URL/project/project-id")
GAR_REGION="europe-west1"

echo "Deploying version: $VERSION from $GAR_REPOSITORY"

# 4. Création de l'arborescence
sudo mkdir -p /home/ubuntu/monitoring/grafana/provisioning
sudo mkdir -p /home/ubuntu/data /home/ubuntu/models
sudo chown -R ubuntu:ubuntu /home/ubuntu

# 5. Fichier Prometheus
cat <<EOF > /home/ubuntu/monitoring/prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'fraud-api'
    static_configs:
      - targets: ['api:8001']
EOF

# 6. Authentification Registry
gcloud auth configure-docker ${GAR_REGION}-docker.pkg.dev --quiet

# 7. Docker Compose
cat <<EOF > /home/ubuntu/docker-compose.yml
services:
  mlflow:
    image: ghcr.io/mlflow/mlflow:v3.9.0
    container_name: fraud-mlflow
    command: >
      mlflow server
      --host 0.0.0.0
      --port 5000
      --backend-store-uri sqlite:///mlflow/mlflow.db
      --allowed-hosts '*'
      --default-artifact-root /mlflow/artifacts
    ports:
      - "5001:5000"
    volumes:
      - mlflow_data:/mlflow
      
  train:
    image: ${GAR_REGION}-docker.pkg.dev/${PROJECT_ID}/${GAR_REPOSITORY}/fraud-train:${VERSION}
    container_name: fraud-train
    environment:
      - MLFLOW_TRACKING_URI=http://mlflow:5000
    depends_on:
      - mlflow
    volumes:
      - /home/ubuntu/data:/app/data
      - /home/ubuntu/models:/app/models
      - mlflow_data:/mlflow

  api:
    image: ${GAR_REGION}-docker.pkg.dev/${PROJECT_ID}/${GAR_REPOSITORY}/fraud-api:${VERSION}
    container_name: fraud-api
    environment:
      - MLFLOW_TRACKING_URI=http://mlflow:5000
      - MLFLOW_MODEL_NAME=fraud-model
      - MODEL_VERSION=v1
      - PRED_THRESHOLD=0.01
      - LOG_LEVEL=INFO
    ports:
      - "8001:8001"
    depends_on:
      - mlflow
    volumes:
      - mlflow_data:/mlflow

  prometheus:
    image: prom/prometheus:v2.54.0
    container_name: fraud-prometheus
    volumes:
      - /home/ubuntu/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9092:9090"
    depends_on:
      - api

  grafana:
    image: grafana/grafana:10.4.2
    container_name: fraud-grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    ports:
      - "3002:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus

  ui:
    image: ${GAR_REGION}-docker.pkg.dev/${PROJECT_ID}/${GAR_REPOSITORY}/fraud-ui:${VERSION}
    container_name: fraud-ui
    environment:
      - API_URL=http://api:8001
      - MLFLOW_URL=http://mlflow:5000
    ports:
      - "8501:8501"
    depends_on:
      - api

volumes:
  grafana_data:
  mlflow_data:
EOF

gsutil -m rsync -r gs://bucket-mlops-junia/monitoring /home/ubuntu/monitoring

gsutil -m rsync -r gs://bucket-mlops-junia/data/ /home/ubuntu/data
sudo chown -R ubuntu:ubuntu /home/ubuntu/data

# 8. Lancement
cd /home/ubuntu
sudo docker compose pull
sudo docker compose up -d

echo "=== Deploy finished at $(date) ==="

