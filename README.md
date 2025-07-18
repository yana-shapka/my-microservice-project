# CI/CD Platform з Jenkins + Argo CD + Terraform + RDS

## Опис проєкту

Цей проєкт реалізує повний CI/CD процес для Django застосунку з використанням:
- **Terraform** для управління інфраструктурою
- **Jenkins** для Continuous Integration (збірка та публікація Docker образів)
- **Argo CD** для Continuous Deployment (GitOps підхід)
- **Kubernetes (EKS)** як платформа оркестрації
- **Helm** для управління конфігураціями Kubernetes
- **🆕 RDS/Aurora** для баз даних (універсальний модуль)

## Архітектура системи

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Developer │────│     Git     │────│   Jenkins   │────│     ECR     │
│   (commit)  │    │ Repository  │    │ (CI/Build)  │    │ (Registry)  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                           │                                      │
                           │                                      │
                           ▼                                      ▼
                   ┌─────────────┐                        ┌─────────────┐
                   │   Argo CD   │◄───────────────────────│ Kubernetes  │
                   │  (GitOps)   │                        │    (EKS)    │
                   └─────────────┘                        └─────────────┘
                           │                                      │
                           │                                      │
                           ▼                                      ▼
                   ┌─────────────┐                        ┌─────────────┐
                   │ RDS/Aurora  │◄───────────────────────│   Django    │
                   │ PostgreSQL  │                        │Application  │
                   └─────────────┘                        └─────────────┘
```

## Структура проєкту

```
my-microservice-project/
│
├── main.tf                  # Головний файл для підключення модулів
├── backend.tf               # Налаштування бекенду для стейтів
├── outputs.tf               # Загальні виводи ресурсів
├── kubernetes-secrets.yaml  # Секрети для Jenkins (AWS credentials)
│
├── modules/                 # Каталог з усіма модулями
│   ├── s3-backend/          # Модуль для S3 та DynamoDB
│   │   ├── s3.tf
│   │   ├── dynamodb.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── vpc/                 # Модуль для VPC
│   │   ├── vpc.tf
│   │   ├── routes.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ecr/                 # Модуль для ECR
│   │   ├── ecr.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── eks/                 # Модуль для Kubernetes кластера
│   │   ├── eks.tf
│   │   ├── aws_ebs_csi_driver.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── 🆕 rds/              # 🆕 Універсальний модуль для RDS/Aurora
│   │   ├── variables.tf     # Змінні модуля
│   │   ├── shared.tf        # Спільні ресурси (Security Group, Subnet Group, etc.)
│   │   ├── rds.tf           # RDS Instance ресурси
│   │   ├── aurora.tf        # Aurora Cluster ресурси
│   │   └── outputs.tf       # Виводи модуля
│   │
│   ├── jenkins/             # Модуль для Jenkins
│   │   ├── jenkins.tf
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── values.yaml
│   │   └── outputs.tf
│   │
│   └── argo_cd/             # Модуль для Argo CD
│       ├── argo_cd.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── values.yaml
│       ├── outputs.tf
│       └── charts/          # Helm chart для Argo CD Applications
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
│               ├── application.yaml
│               └── repository.yaml
│
├── charts/                  # Django Helm Chart
│   └── django-app/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── configmap.yaml
│           ├── hpa.yaml
│           └── _helpers.tpl
│
└── README.md               # Документація проєкту
```

## 🆕 Універсальний RDS модуль

### Опис модуля

Модуль `rds` забезпечує універсальне створення баз даних AWS:
- **RDS Instance** (when `use_aurora = false`)
- **Aurora Cluster** (when `use_aurora = true`)

Автоматично створює всі необхідні ресурси: DB Subnet Group, Security Group, Parameter Group, KMS ключі.

### Приклад використання модуля

#### PostgreSQL RDS Instance (Development)

```terraform
module "rds_postgres_dev" {
  source = "./modules/rds"
  
  # Основні параметри
  project_name = "my-project"
  environment  = "dev"
  
  # Тип БД - RDS Instance
  use_aurora     = false
  engine         = "postgres"
  engine_version = "15.13"
  instance_class = "db.t3.micro"
  
  # Конфігурація БД
  db_name         = "myapp_dev"
  master_username = "appuser"
  master_password = null  # Автогенерація паролю
  
  # Мережа
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  allowed_cidr_blocks = ["10.0.0.0/16"]
  
  # Налаштування для dev середовища
  multi_az                = false
  storage_encrypted       = true
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  
  # Кастомні параметри
  custom_db_parameters = [
    {
      name  = "checkpoint_completion_target"
      value = "0.9"
    }
  ]
  
  tags = {
    Environment = "dev"
    Purpose     = "django-database"
  }
}
```

#### Aurora MySQL Cluster (Production)

```terraform
module "rds_aurora_prod" {
  source = "./modules/rds"
  
  # Основні параметри
  project_name = "my-project"
  environment  = "prod"
  
  # Тип БД - Aurora Cluster
  use_aurora     = true
  engine         = "mysql"
  engine_version = "8.0.mysql_aurora.3.02.0"
  instance_class = "db.r5.large"
  
  # Конфігурація БД
  db_name         = "myapp_prod"
  master_username = "appuser"
  master_password = "MySecurePassword123!"
  
  # Мережа
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  allowed_security_group_ids = [aws_security_group.app.id]
  
  # Aurora specific налаштування
  aurora_replica_count = 2
  
  # Налаштування для production
  multi_az                = true
  storage_encrypted       = true
  backup_retention_period = 30
  deletion_protection     = true
  skip_final_snapshot     = false
  
  # Моніторинг
  performance_insights_enabled = true
  monitoring_interval = 60
  
  tags = {
    Environment = "prod"
    Purpose     = "django-database-prod"
  }
}
```

### Змінні модуля RDS

#### Основні параметри

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `project_name` | string | "lesson-7" | Назва проекту |
| `environment` | string | "dev" | Середовище (dev/staging/prod) |
| `use_aurora` | bool | false | **Ключова змінна**: true = Aurora, false = RDS |

#### Конфігурація двигуна БД

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `engine` | string | "postgres" | Двигун БД: "postgres" або "mysql" |
| `engine_version` | string | "13.7" | Версія двигуна БД |
| `instance_class` | string | "db.t3.micro" | Клас інстансу БД |

#### Конфігурація БД

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `db_name` | string | "djangodb" | Назва бази даних |
| `master_username` | string | "admin" | Ім'я головного користувача |
| `master_password` | string | null | Пароль (null = автогенерація) |
| `port` | number | null | Порт (автоматично: 5432 для postgres, 3306 для mysql) |

#### Мережа та безпека

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `vpc_id` | string | - | **Обов'язкова**: ID VPC |
| `subnet_ids` | list(string) | - | **Обов'язкова**: ID приватних підмереж |
| `allowed_cidr_blocks` | list(string) | [] | CIDR блоки з доступом до БД |
| `allowed_security_group_ids` | list(string) | [] | Security Group ID з доступом до БД |

#### Налаштування зберігання

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `allocated_storage` | number | 20 | Розмір сховища в GB (тільки для RDS) |
| `storage_type` | string | "gp2" | Тип сховища (тільки для RDS) |
| `storage_encrypted` | bool | true | Шифрування сховища |

#### High Availability

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `multi_az` | bool | false | Multi-AZ розгортання |
| `aurora_replica_count` | number | 1 | Кількість Aurora реплік (тільки для Aurora) |

#### Backup та Maintenance

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `backup_retention_period` | number | 7 | Період зберігання бекапів (дні) |
| `backup_window` | string | "03:00-04:00" | Вікно для бекапів |
| `maintenance_window` | string | "sun:04:00-sun:05:00" | Вікно для обслуговування |
| `deletion_protection` | bool | false | Захист від видалення |
| `skip_final_snapshot` | bool | true | Пропустити фінальний snapshot |

#### Моніторинг

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `monitoring_interval` | number | 0 | Інтервал розширеного моніторингу (сек) |
| `performance_insights_enabled` | bool | false | Увімкнути Performance Insights |

#### Кастомні параметри

| Змінна | Тип | За замовчуванням | Опис |
|--------|-----|------------------|------|
| `custom_db_parameters` | list(object) | [] | Список кастомних параметрів БД |

```terraform
# Приклад custom_db_parameters
custom_db_parameters = [
  {
    name  = "max_connections"
    value = "200"
  },
  {
    name  = "checkpoint_completion_target"
    value = "0.9"
  }
]
```

### Як змінити тип БД, engine, клас інстансу

#### 1. Зміна типу БД (RDS ↔ Aurora)

```terraform
# RDS Instance
module "my_database" {
  source = "./modules/rds"
  use_aurora = false  # Використовувати RDS Instance
  # ...
}

# Aurora Cluster
module "my_database" {
  source = "./modules/rds"
  use_aurora = true   # Використовувати Aurora Cluster
  # ...
}
```

#### 2. Зміна engine (PostgreSQL ↔ MySQL)

```terraform
# PostgreSQL
module "my_database" {
  source = "./modules/rds"
  engine         = "postgres"
  engine_version = "15.13"
  # ...
}

# MySQL
module "my_database" {
  source = "./modules/rds"
  engine         = "mysql"
  engine_version = "8.0.35"
  # ...
}

# Aurora PostgreSQL
module "my_database" {
  source = "./modules/rds"
  use_aurora     = true
  engine         = "postgres"
  engine_version = "15.13"
  # ...
}

# Aurora MySQL
module "my_database" {
  source = "./modules/rds"
  use_aurora     = true
  engine         = "mysql"
  engine_version = "8.0.mysql_aurora.3.02.0"
  # ...
}
```

#### 3. Зміна класу інстансу

```terraform
# Development (дешево)
module "my_database" {
  source = "./modules/rds"
  instance_class = "db.t3.micro"    # 2 vCPU, 1 GB RAM
  # ...
}

# Staging (середнє)
module "my_database" {
  source = "./modules/rds"
  instance_class = "db.t3.medium"   # 2 vCPU, 4 GB RAM
  # ...
}

# Production (потужно)
module "my_database" {
  source = "./modules/rds"
  instance_class = "db.r5.xlarge"   # 4 vCPU, 32 GB RAM
  # ...
}

# Aurora specific classes
module "my_database" {
  source = "./modules/rds"
  use_aurora     = true
  instance_class = "db.r5.large"    # Рекомендовано для Aurora
  # ...
}
```

#### 4. Перевірка доступних версій та класів

```bash
# Перевірити доступні версії PostgreSQL
aws rds describe-db-engine-versions --engine postgres --region eu-north-1 --query 'DBEngineVersions[*].EngineVersion'

# Перевірити доступні версії Aurora PostgreSQL
aws rds describe-db-engine-versions --engine aurora-postgresql --region eu-north-1 --query 'DBEngineVersions[*].EngineVersion'

# Перевірити доступні класи інстансів
aws rds describe-orderable-db-instance-options --engine postgres --region eu-north-1 --query 'OrderableDBInstanceOptions[*].DBInstanceClass' | sort | uniq
```

## Створювана інфраструктура

### AWS Ресурси
- **EKS Cluster** з версією Kubernetes 1.28
- **EC2 Node Group** з інстансами t3.medium (2-6 нод)
- **VPC** з публічними та приватними підмережами
- **ECR Repository** для Docker образів
- **🆕 RDS/Aurora PostgreSQL** для Django застосунку
- **S3 Bucket** для Terraform state
- **DynamoDB Table** для state locking
- **IAM Roles** та політики для всіх сервісів
- **EBS CSI Driver** для persistent volumes

### Kubernetes Ресурси
- **Jenkins** з Kaniko для збірки Docker образів
- **Argo CD** для GitOps деплойменту
- **Django Application** з автоматичним масштабуванням
- **LoadBalancer Services** для зовнішнього доступу
- **Persistent Volumes** для Jenkins data

## Передумови

### Встановлені інструменти:
1. **AWS CLI** з налаштованими credentials
2. **Terraform** (версія >= 1.0)
3. **kubectl** для роботи з Kubernetes
4. **Helm 3** для розгортання charts
5. **Git** для роботи з репозиторіями

### AWS Permissions:
- EKS повні права
- EC2 повні права
- IAM створення ролей
- S3 та DynamoDB права
- ECR повні права
- **🆕 RDS повні права** (створення БД, parameter groups, subnet groups)

## Покрокове розгортання

### Крок 1: Підготовка AWS Credentials

```bash
# Налаштуйте AWS CLI
aws configure

# Отримайте ваш AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
```

### Крок 2: Підготовка секретів

```bash
# Кодування AWS credentials в base64
echo -n "YOUR_AWS_ACCESS_KEY_ID" | base64
echo -n "YOUR_AWS_SECRET_ACCESS_KEY" | base64

# Створіть GitHub Personal Access Token і закодуйте
echo -n "YOUR_GITHUB_TOKEN" | base64
```

Оновіть файл `kubernetes-secrets.yaml` з вашими закодованими значеннями:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: jenkins
type: Opaque
data:
  aws-access-key-id: <BASE64_ENCODED_ACCESS_KEY>
  aws-secret-access-key: <BASE64_ENCODED_SECRET_KEY>
---
apiVersion: v1
kind: Secret
metadata:
  name: github-token
  namespace: jenkins
type: Opaque
data:
  token: <BASE64_ENCODED_GITHUB_TOKEN>
```

### Крок 3: Розгортання інфраструктури

```bash
# Ініціалізація Terraform
terraform init

# Перегляд планованих змін
terraform plan

# Розгортання інфраструктури (20-25 хвилин з RDS)
terraform apply
```

### Крок 4: Налаштування kubectl

```bash
# Налаштування доступу до EKS кластера
aws eks update-kubeconfig --region eu-north-1 --name lesson-7-eks-cluster

# Перевірка підключення
kubectl get nodes
kubectl get namespaces
```

### Крок 5: Застосування секретів

```bash
# Застосування AWS credentials та GitHub token
kubectl apply -f kubernetes-secrets.yaml

# Перевірка створення секретів
kubectl get secrets -n jenkins
```

### 🆕 Крок 6: Налаштування Django для роботи з базою даних

```bash
# Отримання конфігурації БД для Django
terraform output django_database_config

# Створення Kubernetes ConfigMap для Django
kubectl create configmap django-db-config \
  --from-literal=DATABASE_ENGINE=django.db.backends.postgresql \
  --from-literal=DATABASE_NAME=$(terraform output -raw postgres_db_name) \
  --from-literal=DATABASE_USER=$(terraform output -raw postgres_db_username) \
  --from-literal=DATABASE_HOST=$(terraform output -raw postgres_db_endpoint | cut -d: -f1) \
  --from-literal=DATABASE_PORT=$(terraform output -raw postgres_db_port) \
  --namespace=django-app

# Створення Kubernetes Secret з паролем БД
kubectl create secret generic django-db-secret \
  --from-literal=DATABASE_PASSWORD="$(terraform output -raw postgres_db_password)" \
  --namespace=django-app
```

### Крок 7: Доступ до сервісів

```bash
# Отримання URLs та паролів
terraform output deployment_instructions

# Отримання паролів окремо
terraform output jenkins_admin_password
terraform output argocd_admin_password
terraform output postgres_db_password
```

## Налаштування CI/CD Pipeline

### 1. Налаштування Jenkins

**Доступ до Jenkins UI:**
```bash
# Отримати URL Jenkins
terraform output jenkins_url
```

**Логін в Jenkins:**
- Username: `admin`
- Password: `terraform output jenkins_admin_password`

**Створення Pipeline Job:**
- New Item → Pipeline
- Pipeline script from SCM
- Git Repository: `https://github.com/yana-shapka/my-microservice-project.git`
- Branch: `lesson-4`
- Script Path: `Jenkinsfile`

**Налаштування Credentials:**
- Manage Jenkins → Credentials
- Додайте GitHub token з ID: `github-token`

### 2. Налаштування Argo CD

**Доступ до Argo CD UI:**
```bash
# Отримати URL Argo CD
terraform output argocd_server_url
```

**Логін в Argo CD:**
- Username: `admin`
- Password: `terraform output argocd_admin_password`

**Перевірка Applications:**
- Argo CD автоматично створить Application для Django
- Перевірте статус синхронізації

## Процес CI/CD

### Continuous Integration (Jenkins)

1. **Тригер:** Push в гілку `lesson-4`
2. **Збірка:** Kaniko збирає Docker образ з Django кодом
3. **Публікація:** Образ публікується в ECR з тегом build number
4. **Оновлення:** Jenkins оновлює `values.yaml` в гілці `cicd-project`
5. **Commit:** Зміни комітяться назад в Git репозиторій

### Continuous Deployment (Argo CD)

1. **Моніторинг:** Argo CD стежить за змінами в `cicd-project` гілці
2. **Синхронізація:** Автоматично застосовує зміни в Kubernetes
3. **Деплой:** Новий Docker образ розгортається в кластері
4. **🆕 Підключення до БД:** Django застосунок підключається до PostgreSQL
5. **Масштабування:** HPA автоматично масштабує поди при навантаженні

## 🆕 Робота з базою даних

### Підключення до PostgreSQL

```bash
# Отримання connection string
terraform output postgres_connection_string

# Підключення через psql
psql "$(terraform output -raw postgres_connection_string)"

# Або окремими параметрами
psql -h $(terraform output -raw postgres_db_endpoint | cut -d: -f1) \
     -p $(terraform output -raw postgres_db_port) \
     -U $(terraform output -raw postgres_db_username) \
     -d $(terraform output -raw postgres_db_name)
```

### Django міграції

```bash
# В Django контейнері виконайте
python manage.py migrate
python manage.py createsuperuser
```

## Моніторинг та логування

### Перевірка статусу
```bash
# Jenkins pods
kubectl get pods -n jenkins

# Argo CD pods
kubectl get pods -n argocd

# Django application
kubectl get pods -n django-app

# 🆕 Перевірка підключення до БД
kubectl logs -f deployment/django-app -n django-app | grep -i database

# Services та їх external IPs
kubectl get services --all-namespaces
```

### Логи
```bash
# Jenkins logs
kubectl logs -f deployment/jenkins -n jenkins

# Argo CD logs
kubectl logs -f deployment/argocd-server -n argocd

# Django application logs
kubectl logs -f deployment/django-app -n django-app
```

### 🆕 Моніторинг бази даних

```bash
# PostgreSQL статус
aws rds describe-db-instances --db-instance-identifier lesson-7-dev-db --region eu-north-1

# CloudWatch метрики
aws logs describe-log-groups --log-group-name-prefix "/aws/rds/instance/lesson-7-dev-db" --region eu-north-1

# Performance Insights (якщо увімкнено)
aws pi get-resource-metrics --service-type RDS --identifier $(terraform output -raw postgres_db_endpoint | cut -d. -f1) --region eu-north-1
```

### Метрики
```bash
# Node metrics
kubectl top nodes

# Pod metrics
kubectl top pods --all-namespaces

# HPA status
kubectl get hpa -n django-app

# 🆕 Database connections in Django
kubectl exec -it deployment/django-app -n django-app -- python manage.py dbshell --command="SELECT count(*) FROM pg_stat_activity;"
```

## Автоматичне масштабування

Django застосунок налаштований з HorizontalPodAutoscaler:
- **Мінімум подів:** 2
- **Максимум подів:** 6
- **Поріг CPU:** 70%
- **Метрики:** CPU utilization

```bash
# Моніторинг автомасштабування
kubectl describe hpa django-app -n django-app
watch kubectl get hpa -n django-app
```

## Безпека

### Реалізовані заходи:
- **RBAC:** Роль-базований контроль доступу для всіх сервісів
- **Service Accounts:** Окремі service accounts для Jenkins та Argo CD
- **Secrets Management:** AWS credentials та GitHub tokens в Kubernetes secrets
- **🆕 Database Security:** RDS в приватних підмережах, Security Groups, шифрування
- **Network Policies:** Ізоляція мережевого трафіку
- **Image Scanning:** ECR автоматично сканує образи на вразливості

### Рекомендації для production:
- Використовуйте AWS Secrets Manager замість Kubernetes secrets
- Налаштуйте Vault для управління секретами
- Увімкніть Pod Security Standards
- Налаштуйте Network Policies для строгої ізоляції
- Використовуйте private ECR endpoints
- **🆕 Увімкніть RDS encryption at rest та in transit**
- **🆕 Налаштуйте RDS backup та point-in-time recovery**
- **🆕 Використовуйте RDS Proxy для connection pooling**

## Вартість ресурсів

### Приблизна вартість (за годину):
- **EKS Control Plane:** $0.10
- **EC2 t3.medium (2 nodes):** $0.08
- **🆕 RDS db.t3.micro:** $0.017
- **NAT Gateways (3):** $0.135
- **LoadBalancers (3):** $0.068
- **EBS Volumes:** $0.01

**🆕 Загальна вартість:** ~$0.41/година або ~$295/місяць

### Оптимізація витрат:
- Використовуйте Spot Instances для worker nodes
- Налаштуйте Cluster Autoscaler
- Використовуйте один NAT Gateway для dev середовища
- Налаштуйте automatic shutdown для dev кластерів
- **🆕 Використовуйте RDS Reserved Instances для production**
- **🆕 Налаштуйте автоматичне backup rotation**

## Troubleshooting

### Поширені проблеми:

#### Jenkins не може збудувати образ
```bash
# Перевірити права Kaniko
kubectl describe pod -l app=jenkins -n jenkins
kubectl logs -f pod/jenkins-kaniko-xxx -n jenkins
```

#### Argo CD не синхронізує зміни
```bash
# Перевірити статус application
kubectl get applications -n argocd
kubectl describe application django-app -n argocd

# Перевірити логи Argo CD
kubectl logs -f deployment/argocd-application-controller -n argocd
```

#### Django поди не запускаються
```bash
# Перевірити статус подів
kubectl get pods -n django-app
kubectl describe pod django-app-xxx -n django-app

# Перевірити образ в ECR
aws ecr describe-images --repository-name lesson-7-django-app --region eu-north-1
```

#### 🆕 Django не може підключитися до БД
```bash
# Перевірити конфігурацію БД
kubectl get configmap django-db-config -n django-app -o yaml
kubectl get secret django-db-secret -n django-app -o yaml

# Перевірити security groups
aws ec2 describe-security-groups --group-ids $(terraform output -raw postgres_security_group_id) --region eu-north-1

# Тестувати підключення з pods
kubectl exec -it deployment/django-app -n django-app -- python manage.py dbshell

# Перевірити RDS статус
aws rds describe-db-instances --db-instance-identifier lesson-7-dev-db --region eu-north-1 --query 'DBInstances[0].DBInstanceStatus'
```

#### LoadBalancer не отримує external IP
```bash
# Перевірити service
kubectl describe service jenkins -n jenkins
kubectl describe service argocd-server -n argocd

# Перевірити AWS Load Balancers в консолі
aws elbv2 describe-load-balancers --region eu-north-1
```

#### 🆕 RDS Parameter Group помилки
```bash
# Перевірити існуючі parameter groups
aws rds describe-db-parameter-groups --region eu-north-1

# Видалити конфліктний parameter group
aws rds delete-db-parameter-group --db-parameter-group-name lesson-7-dev-db-params --region eu-north-1

# Імпортувати існуючий в Terraform state
terraform import module.rds_postgres.aws_db_parameter_group.main[0] lesson-7-dev-db-params
```

#### 🆕 Проблеми з версіями PostgreSQL/MySQL
```bash
# Перевірити доступні версії
aws rds describe-db-engine-versions --engine postgres --region eu-north-1 --query 'DBEngineVersions[*].EngineVersion'

# Для Aurora
aws rds describe-db-engine-versions --engine aurora-postgresql --region eu-north-1 --query 'DBEngineVersions[*].EngineVersion'
```

### Відновлення після помилок:

#### Очищення та перезапуск
```bash
# Перезапуск Jenkins
kubectl rollout restart deployment/jenkins -n jenkins

# Перезапуск Argo CD
kubectl rollout restart deployment/argocd-server -n argocd

# 🆕 Перезапуск Django з новими DB credentials
kubectl delete secret django-db-secret -n django-app
kubectl create secret generic django-db-secret \
  --from-literal=DATABASE_PASSWORD="$(terraform output -raw postgres_db_password)" \
  --namespace=django-app
kubectl rollout restart deployment/django-app -n django-app

# Повне пересинхронізування в Argo CD
kubectl patch application django-app -n argocd --type merge --patch='{"operation":{"initiatedBy":{"automated":true}}}'
```

#### 🆕 Відновлення БД з backup
```bash
# Список доступних snapshots
aws rds describe-db-snapshots --db-instance-identifier lesson-7-dev-db --region eu-north-1

# Відновлення з автоматичного backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier lesson-7-dev-db-restored \
  --db-snapshot-identifier rds:lesson-7-dev-db-2025-01-18-03-00 \
  --region eu-north-1

# Point-in-time recovery
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier lesson-7-dev-db \
  --target-db-instance-identifier lesson-7-dev-db-restored \
  --restore-time 2025-01-18T10:00:00.000Z \
  --region eu-north-1
```

## 🆕 Тестування модуля RDS

### Тестування RDS Instance

```bash
# 1. Створення з PostgreSQL
terraform apply -target=module.rds_postgres

# 2. Перевірка створення
aws rds describe-db-instances --db-instance-identifier lesson-7-dev-db --region eu-north-1

# 3. Тестування підключення
psql -h $(terraform output -raw postgres_db_endpoint | cut -d: -f1) \
     -p $(terraform output -raw postgres_db_port) \
     -U $(terraform output -raw postgres_db_username) \
     -d $(terraform output -raw postgres_db_name)
```

### Тестування Aurora Cluster

```bash
# 1. Зміна конфігурації на Aurora
# В main.tf змінити: use_aurora = true

# 2. Застосування змін
terraform apply -target=module.rds_postgres

# 3. Перевірка Aurora cluster
aws rds describe-db-clusters --db-cluster-identifier lesson-7-dev-aurora-cluster --region eu-north-1

# 4. Перевірка instances в cluster
aws rds describe-db-cluster-members --db-cluster-identifier lesson-7-dev-aurora-cluster --region eu-north-1
```

### Тестування з різними engines

```bash
# MySQL RDS
terraform apply -var="engine=mysql" -var="engine_version=8.0.35" -target=module.rds_postgres

# Aurora MySQL
terraform apply -var="use_aurora=true" -var="engine=mysql" -var="engine_version=8.0.mysql_aurora.3.02.0" -target=module.rds_postgres
```

## 🆕 Конфігурація Django для різних БД

### PostgreSQL конфігурація

```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('DATABASE_NAME', 'djangodb'),
        'USER': os.environ.get('DATABASE_USER', 'djangouser'),
        'PASSWORD': os.environ.get('DATABASE_PASSWORD'),
        'HOST': os.environ.get('DATABASE_HOST', 'localhost'),
        'PORT': os.environ.get('DATABASE_PORT', '5432'),
        'OPTIONS': {
            'conn_max_age': 60,
            'sslmode': 'require',
        }
    }
}
```

### MySQL конфігурація

```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': os.environ.get('DATABASE_NAME', 'djangodb'),
        'USER': os.environ.get('DATABASE_USER', 'djangouser'),
        'PASSWORD': os.environ.get('DATABASE_PASSWORD'),
        'HOST': os.environ.get('DATABASE_HOST', 'localhost'),
        'PORT': os.environ.get('DATABASE_PORT', '3306'),
        'OPTIONS': {
            'charset': 'utf8mb4',
            'init_command': "SET sql_mode='STRICT_TRANS_TABLES'",
        }
    }
}
```

### Aurora з Read Replicas

```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('DATABASE_NAME'),
        'USER': os.environ.get('DATABASE_USER'),
        'PASSWORD': os.environ.get('DATABASE_PASSWORD'),
        'HOST': os.environ.get('DATABASE_HOST'),  # Writer endpoint
        'PORT': os.environ.get('DATABASE_PORT', '5432'),
    },
    'read_replica': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('DATABASE_NAME'),
        'USER': os.environ.get('DATABASE_USER'),
        'PASSWORD': os.environ.get('DATABASE_PASSWORD'),
        'HOST': os.environ.get('DATABASE_READ_HOST'),  # Reader endpoint
        'PORT': os.environ.get('DATABASE_PORT', '5432'),
    }
}

# Database router для read replicas
DATABASE_ROUTERS = ['myapp.routers.DatabaseRouter']
```

## 🆕 Приклади використання для різних сценаріїв

### Development Environment

```terraform
module "rds_dev" {
  source = "./modules/rds"
  
  project_name = "myapp"
  environment  = "dev"
  
  # Мінімальна конфігурація для розробки
  use_aurora     = false
  engine         = "postgres"
  engine_version = "15.13"
  instance_class = "db.t3.micro"
  
  # Дешеві налаштування для dev
  multi_az                = false
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  storage_encrypted       = false  # Можна вимкнути для dev
  
  # Мережа
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  allowed_cidr_blocks = [module.vpc.vpc_cidr_block]
}
```

### Staging Environment

```terraform
module "rds_staging" {
  source = "./modules/rds"
  
  project_name = "myapp"
  environment  = "staging"
  
  # Середня конфігурація
  use_aurora     = false
  engine         = "postgres"
  engine_version = "15.13"
  instance_class = "db.t3.medium"
  
  # Staging налаштування
  multi_az                = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = false
  storage_encrypted       = true
  
  # Моніторинг
  performance_insights_enabled = true
  monitoring_interval = 60
  
  # Мережа
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
}
```

### Production Environment

```terraform
module "rds_production" {
  source = "./modules/rds"
  
  project_name = "myapp"
  environment  = "prod"
  
  # Aurora для high availability
  use_aurora     = true
  engine         = "postgres"
  engine_version = "15.13"
  instance_class = "db.r5.xlarge"
  
  # Production налаштування
  aurora_replica_count = 3
  multi_az                = true
  backup_retention_period = 30
  deletion_protection     = true
  skip_final_snapshot     = false
  storage_encrypted       = true
  
  # Повний моніторинг
  performance_insights_enabled = true
  monitoring_interval = 60
  
  # Кастомні параметри для performance
  custom_db_parameters = [
    {
      name  = "max_connections"
      value = "500"
    },
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    },
    {
      name  = "checkpoint_completion_target"
      value = "0.9"
    }
  ]
  
  # Мережа
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
}
```

## Очищення ресурсів

**ВАЖЛИВО:** Для уникнення непередбачуваних витрат завжди видаляйте ресурси після тестування.

```bash
# Видалення Helm releases
helm uninstall jenkins -n jenkins
helm uninstall argocd -n argocd
helm uninstall django-app -n django-app

# Видалення Terraform інфраструктури
terraform destroy

# 🆕 Форсоване видалення RDS (якщо Terraform destroy не спрацював)
aws rds delete-db-instance --db-instance-identifier lesson-7-dev-db --skip-final-snapshot --region eu-north-1

# 🆕 Видалення Aurora cluster
aws rds delete-db-cluster --db-cluster-identifier lesson-7-dev-aurora-cluster --skip-final-snapshot --region eu-north-1

# Підтвердження видалення в AWS Console
# Перевірити: EKS, EC2, LoadBalancers, NAT Gateways, RDS
```

### 🆕 Швидка перевірка видалення ресурсів

```bash
# Перевірити що все видалено
echo "=== EKS Clusters ==="
aws eks list-clusters --region eu-north-1

echo "=== RDS Instances ==="
aws rds describe-db-instances --region eu-north-1 --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'

echo "=== Aurora Clusters ==="
aws rds describe-db-clusters --region eu-north-1 --query 'DBClusters[*].[DBClusterIdentifier,Status]'

echo "=== Load Balancers ==="
aws elbv2 describe-load-balancers --region eu-north-1 --query 'LoadBalancers[*].[LoadBalancerName,State.Code]'

echo "=== NAT Gateways ==="
aws ec2 describe-nat-gateways --region eu-north-1 --query 'NatGateways[?State!=`deleted`].[NatGatewayId,State]'

echo "=== EIP Addresses ==="
aws ec2 describe-addresses --region eu-north-1 --query 'Addresses[*].[AllocationId,InstanceId]'
```

## 🆕 Outputs модуля RDS

Після успішного створення RDS модуля ви отримаєте наступні outputs:

```bash
# Universal outputs (працюють для RDS і Aurora)
terraform output postgres_db_endpoint
terraform output postgres_db_port
terraform output postgres_db_name
terraform output postgres_db_username
terraform output postgres_db_password      # sensitive
terraform output postgres_connection_string # sensitive

# Django specific
terraform output django_database_config    # готова конфігурація для Django
terraform output django_database_password  # sensitive

# Infrastructure info
terraform output postgres_security_group_id

# Aurora specific (якщо use_aurora = true)
terraform output aurora_cluster_endpoint
terraform output aurora_cluster_reader_endpoint
terraform output aurora_writer_instance_endpoint
terraform output aurora_reader_instance_endpoints
```

---
