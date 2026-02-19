# Fraud Detection — MLOps Deployment (GCP)

Dépôt d'**Infrastructure as Code (IaC)** pour le déploiement automatisé de la plateforme MLOps de détection de fraude sur **Google Cloud Platform**.

Ce repo ne contient **aucun code applicatif**. Les images Docker sont buildées dans un repo séparé, pushées sur Google Artifact Registry, puis déployées ici via Terraform et un startup-script.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform                        │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              VM : app-server-vm (e2-standard-4)           │  │
│  │              Ubuntu 22.04 LTS — europe-west1-b            │  │
│  │                                                           │  │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐                │  │
│  │   │  MLflow  │  │  Train   │  │   API    │                │  │
│  │   │  :5001   │  │ one-shot │  │  :8001   │                │  │
│  │   └──────────┘  └──────────┘  └──────────┘                │  │
│  │                                                           │  │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐                │  │
│  │   │Prometheus│  │ Grafana  │  │    UI    │                │  │
│  │   │  :9092   │  │  :3002   │  │  :8501   │                │  │
│  │   └──────────┘  └──────────┘  └──────────┘                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────┐   ┌──────────────────────────────────────┐ │
│  │  GCS Bucket     │   │  Artifact Registry (mlops-depots)    │ │
│  │  bucket-mlops-  │   │  fraud-api / fraud-train / fraud-ui  │ │
│  │  junia          │   └──────────────────────────────────────┘ │
│  └─────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Services déployés sur la VM

| Service | Image | Port | Description |
|---------|-------|------|-------------|
| **MLflow** | `ghcr.io/mlflow/mlflow:v3.9.0` | 5001 | Tracking server pour les expériences ML |
| **Train** | `fraud-train:latest` | — | Entraîne le modèle et l'enregistre dans MLflow (one-shot) |
| **API** | `fraud-api:latest` | 8001 | API FastAPI de prédiction de fraude |
| **UI** | `fraud-ui:latest` | 8501 | Interface Streamlit |
| **Prometheus** | `prom/prometheus:v2.54.0` | 9092 | Collecte des métriques |
| **Grafana** | `grafana/grafana:10.4.2` | 3002 | Dashboards de monitoring |

---

## Structure du projet

```
.
├── .github/
│   └── workflows/
│       └── gcp-deploy.yml          # Workflow GitHub Actions (CI/CD)
├── terraform/
│   ├── main.tf                     # VM Compute Engine, Service Account, IAM
│   ├── network.tf                  # VPC, Subnet, Firewall rules
│   ├── variables.tf                # Variables Terraform
│   ├── terraform.tfvars            # Valeurs des variables
│   ├── output.tf                   # Output : IP publique de la VM
│   └── scripts/
│       ├── deploy.sh               # Startup-script exécuté sur la VM
│       └── docker-compose.yml      # Référence du docker-compose
└── README.md
```

---

## Prérequis

### Outils locaux

| Outil | Version | Installation |
|-------|---------|--------------|
| **Terraform** | >= 1.0 | `brew install terraform` |
| **gcloud CLI** | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| **Git** | latest | `brew install git` |

### Ressources GCP

- Un **projet GCP** avec la facturation activée
- Les **APIs** suivantes activées :
  ```bash
  gcloud services enable compute.googleapis.com
  gcloud services enable iam.googleapis.com
  gcloud services enable cloudresourcemanager.googleapis.com
  gcloud services enable artifactregistry.googleapis.com
  gcloud services enable storage.googleapis.com
  ```
- Un **bucket GCS** `bucket-mlops-junia` pour le state Terraform et les données :
  ```bash
  gsutil mb -l europe-west1 gs://bucket-mlops-junia
  ```
- Un **Artifact Registry** `mlops-depots` contenant les images Docker :
  ```bash
  gcloud artifacts repositories create mlops-depots \
    --repository-format=docker \
    --location=europe-west1
  ```
- Les **images Docker** suivantes pushées sur Artifact Registry :
  - `europe-west1-docker.pkg.dev/<PROJECT_ID>/mlops-depots/fraud-api:latest`
  - `europe-west1-docker.pkg.dev/<PROJECT_ID>/mlops-depots/fraud-train:latest`
  - `europe-west1-docker.pkg.dev/<PROJECT_ID>/mlops-depots/fraud-ui:latest`

- Les **données** uploadées sur GCS :
  ```bash
  gsutil cp -r data/ gs://bucket-mlops-junia/data/
  gsutil cp -r monitoring/ gs://bucket-mlops-junia/monitoring/
  ```

### Secrets GitHub Actions

| Secret | Description |
|--------|-------------|
| `GCP_SA_KEY` | JSON de la clé du Service Account GCP (avec les rôles Editor + Storage Admin) |
| `GCP_PROJECT_ID` | ID du projet GCP (ex : `mlops-projects-487817`) |

---

## Déploiement

### Option 1 : Déploiement manuel (Terraform en local)

```bash
# 1. Authentification GCP
gcloud auth application-default login

# 2. Initialiser Terraform
cd terraform/
terraform init

# 3. Vérifier le plan
terraform plan

# 4. Appliquer
terraform apply
```

Terraform affichera l'IP publique de la VM en output :

```
Outputs:
  instance_ip = "34.xxx.xxx.xxx"
```

### Option 2 : Déploiement automatique (GitHub Actions)

1. Allez dans l'onglet **Actions** du repo GitHub
2. Sélectionnez le workflow **"Deploy to GCP"**
3. Cliquez sur **"Run workflow"**
4. (Optionnel) Spécifiez un tag d'image
5. Le workflow exécute `terraform init` → `plan` → `apply`

---

## Accès aux services

Une fois déployé, les services sont accessibles via l'IP publique de la VM :

| Service | URL |
|---------|-----|
| API (FastAPI) | `http://<INSTANCE_IP>:8001` |
| API Docs (Swagger) | `http://<INSTANCE_IP>:8001/docs` |
| MLflow UI | `http://<INSTANCE_IP>:5001` |
| Streamlit UI | `http://<INSTANCE_IP>:8501` |
| Prometheus | `http://<INSTANCE_IP>:9092` |
| Grafana | `http://<INSTANCE_IP>:3002` |

> **Grafana** : login par défaut `admin` / `admin123`

Pour récupérer l'IP :

```bash
cd terraform/
terraform output instance_ip
```

---

## Connexion SSH à la VM

```bash
gcloud compute ssh ubuntu@app-server-vm --zone=europe-west1-b
```

### Commandes utiles sur la VM

```bash
# Voir les logs du déploiement
sudo cat /var/log/deploy.log

# Voir les logs du startup-script
sudo journalctl -u google-startup-scripts.service -f

# Voir les conteneurs en cours
sudo docker compose -f /home/ubuntu/docker-compose.yml ps

# Voir les logs d'un service
sudo docker logs fraud-api
sudo docker logs fraud-train
sudo docker logs fraud-mlflow

# Relancer le déploiement manuellement
sudo bash /var/run/google_metadata_script_runner/startup-script
```

---

## Vérification locale de l'IaC

Avant de déployer, vous pouvez vérifier la configuration en local :

```bash
cd terraform/

# Vérifier le formatage
terraform fmt -check -diff

# Valider la syntaxe (ne contacte pas GCP)
terraform validate

# Simuler le déploiement (nécessite auth GCP)
terraform plan
```

### Outils complémentaires (optionnels)

```bash
# Linting avancé
brew install tflint
tflint

# Analyse de sécurité
brew install checkov
checkov -d .
```

---

## Infrastructure Terraform

### Réseau (`network.tf`)

- **VPC** : `main-vpc` (pas de sous-réseaux automatiques)
- **Subnet** : `public-subnet` — `10.0.1.0/24` dans `europe-west1`
- **Firewall SSH** : ports `22`, `8501`, `5001`, `3002`, `9092`, `8001` ouverts depuis `0.0.0.0/0`
- **Firewall Web** : ports `80`, `443` ouverts depuis `0.0.0.0/0`

### Compute (`main.tf`)

- **VM** : `app-server-vm` — `e2-standard-4`, Ubuntu 22.04, disque 10 GB
- **Service Account** : `app-server-sa` avec le rôle `roles/artifactregistry.reader`
- **Metadata** : tag image, repo, project ID, startup-script

### Variables (`variables.tf`)

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | — (requis) | ID du projet GCP |
| `region` | `europe-west1` | Région GCP |
| `zone` | `europe-west1-b` | Zone GCP |
| `app_image_tag` | `latest` | Tag des images Docker |
| `repository` | `mlops-depots` | Nom du repository Artifact Registry |

---

## Flux de déploiement

```
  Repo applicatif                    Ce repo (deployment)
  ┌─────────────┐                    ┌──────────────────────┐
  │ Push code   │                    │                      │
  │     ↓       │                    │                      │
  │ Build image │  repository_       │ GitHub Actions       │
  │     ↓       │  dispatch          │     ↓                │
  │ Push to GAR │ ──────────────────>│ terraform apply      │
  │             │                    │     ↓                │
  └─────────────┘                    │ VM metadata updated  │
                                     │     ↓                │
                                     │ startup-script runs  │
                                     │     ↓                │
                                     │ docker compose up    │
                                     └──────────────────────┘
```

---

## Destruction de l'infrastructure

```bash
cd terraform/
terraform destroy
```

Vous pouvez le tester aux adresse suivantes : 
- Streamlit : http://35.195.224.172:8501/
- MLflow : http://35.195.224.172:5001/
- Grafana : http://35.195.224.172:3002/
- Prometheus : http://35.195.224.172:9092/

> **Attention** : cela supprime la VM, le réseau, les firewalls et le service account.

---

<!-- ## Dépannage

| Problème | Solution |
|----------|----------|
| `exit status 22` dans le startup-script | Vérifier les metadata : `curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/` |
| Docker non installé | Relancer le startup-script : `sudo bash /var/run/google_metadata_script_runner/startup-script` |
| Conteneur en erreur | `sudo docker logs <nom_conteneur>` |
| API non accessible | Vérifier le firewall : `gcloud compute firewall-rules list` |
| Données manquantes | Vérifier GCS : `gsutil ls gs://bucket-mlops-junia/data/` |
| Terraform state lock | `terraform force-unlock <LOCK_ID>` | -->
