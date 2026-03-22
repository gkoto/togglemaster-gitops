# ToggleMaster - Infraestrutura & DevOps

## Tech Challenge Fase 3 - Pós-Tech FIAP DevOps & Cloud Computing

Projeto completo de infraestrutura como código (Terraform), CI/CD (GitHub Actions) e GitOps (ArgoCD) para a plataforma de feature flags **ToggleMaster**.

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS (us-east-1)                         │
│  ┌──────────────────── VPC 10.0.0.0/16 ──────────────────────┐ │
│  │                                                             │ │
│  │  Public Subnets          Private Subnets                    │ │
│  │  ┌──────────┐            ┌──────────────────────────┐       │ │
│  │  │ NAT GW   │            │  EKS Node Group          │       │ │
│  │  │ IGW      │            │  ┌─────┐ ┌─────┐ ┌────┐ │       │ │
│  │  └──────────┘            │  │auth │ │flag │ │... │ │       │ │
│  │                          │  └─────┘ └─────┘ └────┘ │       │ │
│  │                          └──────────────────────────┘       │ │
│  │                                                             │ │
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────┐              │ │
│  │  │ RDS x3      │  │ Redis    │  │ DynamoDB │  ┌─────┐     │ │
│  │  │ PostgreSQL  │  │ ElastiC. │  │          │  │ SQS │     │ │
│  │  └─────────────┘  └──────────┘  └──────────┘  └─────┘     │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌──────────┐                                                     │
│  │ ECR x5   │  (repositórios de imagens Docker)                   │
│  └──────────┘                                                     │
└───────────────────────────────────────────────────────────────────┘

GitHub Actions (CI) ──push image──> ECR
                     ──update tag──> GitOps Repo
ArgoCD (CD) ──watch──> GitOps Repo ──sync──> EKS
```

---

## Estrutura de Repositórios

Você terá **3 tipos de repositório** no GitHub:

| Repositório | Conteúdo |
|---|---|
| `togglemaster-infra` | Código Terraform (este diretório) |
| `togglemaster-gitops` | Manifestos K8s + ArgoCD |
| 5x repos de microsserviços | Código fonte + `.github/workflows/ci.yml` |

---

## Pré-requisitos

- AWS CLI configurado (`aws configure`)
- Terraform >= 1.5.0
- kubectl
- Git

---

## PASSO A PASSO COMPLETO

### ETAPA 1: Criar o Bucket S3 para o Backend Remoto

O Terraform precisa guardar o estado (tfstate) remotamente. Crie o bucket **antes** de tudo:

```bash
# Troque SEU_ACCOUNT_ID pelo seu Account ID da AWS
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3api create-bucket \
  --bucket togglemaster-tfstate-${ACCOUNT_ID} \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket togglemaster-tfstate-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

echo "Bucket criado: togglemaster-tfstate-${ACCOUNT_ID}"
```

### ETAPA 2: Configurar o Terraform

```bash
cd togglemaster-infra

# 1. Edite o backend no main.tf - troque "togglemaster-tfstate-CHANGE-ME"
#    pelo nome do bucket criado acima
nano main.tf

# 2. Crie o arquivo de variáveis
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # preencha db_password com uma senha forte
```

### ETAPA 3: Aplicar o Terraform

```bash
# Inicializar (baixa providers e configura backend S3)
terraform init

# Ver o plano de execução
terraform plan

# Aplicar (vai demorar ~15-20 minutos por causa do EKS e RDS)
terraform apply

# Salve os outputs! Você vai precisar deles
terraform output -json > ../outputs.json
```

### ETAPA 4: Configurar kubectl

```bash
# O comando exato aparece no output do Terraform
aws eks update-kubeconfig \
  --name togglemaster-prod-eks \
  --region us-east-1

# Verificar conexão
kubectl get nodes
```

### ETAPA 5: Instalar ArgoCD

```bash
cd ../togglemaster-gitops

# Tornar executável e rodar
chmod +x argocd/install-argocd.sh
bash argocd/install-argocd.sh

# Aguardar LoadBalancer (pode demorar 2-3 min)
kubectl get svc argocd-server -n argocd -w
```

### ETAPA 6: Configurar o Repositório GitOps

```bash
# 1. Atualize os ConfigMaps com os outputs do Terraform
#    Substitua "PREENCHA-COM-OUTPUT-TERRAFORM" em base/configmaps.yaml
#    com os valores reais de rds_endpoints, redis_endpoint, sqs_queue_url

# 2. Atualize as imagens nos deployments com o ECR correto
#    Substitua "123456789012" pelo seu Account ID em todos os apps/*/deployment.yaml

# 3. Troque <SEU_USUARIO_GITHUB> em argocd/applications.yaml

# 4. Push pro GitHub
cd togglemaster-gitops
git init
git add .
git commit -m "feat: initial gitops manifests"
git remote add origin https://github.com/<SEU_USUARIO>/togglemaster-gitops.git
git push -u origin main
```

### ETAPA 7: Aplicar os manifestos base e as Applications do ArgoCD

```bash
# Aplicar namespace, configmaps e secrets
kubectl apply -f base/

# Aplicar as Applications do ArgoCD
kubectl apply -f argocd/applications.yaml

# Verificar no ArgoCD UI (acesse a URL do LoadBalancer)
# Login: admin / <senha do passo 5>
```

### ETAPA 8: Configurar CI nos repos dos microsserviços

Para cada um dos 5 repos (`auth-service`, `flag-service`, etc.):

```bash
# 1. Faça fork do repo original para sua conta
# 2. Copie o workflow correto:
#    - Para Go (auth-service, evaluation-service): ci-go.yml
#    - Para Python (flag-service, targeting-service, analytics-service): ci-python.yml
# 3. Renomeie para .github/workflows/ci.yml
# 4. Edite SERVICE_NAME e ECR_REPOSITORY no arquivo

# 5. Configure os Secrets no GitHub (Settings > Secrets > Actions):
#    - AWS_ACCESS_KEY_ID
#    - AWS_SECRET_ACCESS_KEY
#    - GITOPS_PAT (Personal Access Token com acesso ao repo gitops)
```

### ETAPA 9: Testar o Fluxo Completo

```bash
# 1. Faça uma alteração em qualquer microsserviço
# 2. Abra um PR → CI roda (build, lint, security)
# 3. Merge na main → CI faz docker build + push ECR + atualiza gitops
# 4. ArgoCD detecta mudança → sincroniza automaticamente no EKS
# 5. Verifique na UI do ArgoCD que tudo está "Synced" e "Healthy"
```

---

## Custos Estimados (AWS)

> ⚠️ ATENÇÃO: Estes recursos geram custos na AWS!

| Recurso | Custo estimado/mês |
|---|---|
| EKS Cluster | ~$73 |
| 2x t3.medium (nodes) | ~$60 |
| 3x RDS db.t3.micro | ~$45 |
| ElastiCache cache.t3.micro | ~$12 |
| NAT Gateway | ~$32 |
| DynamoDB (on-demand) | ~$1 |
| SQS | ~$0 |
| ECR | ~$1 |
| **TOTAL** | **~$224/mês** |

**Para destruir tudo após a entrega:**
```bash
cd togglemaster-infra
terraform destroy
# Depois delete o bucket S3 manualmente
```

---

## Estrutura do Terraform

```
togglemaster-infra/
├── main.tf                 # Config principal + módulos
├── variables.tf            # Variáveis globais
├── outputs.tf              # Outputs
├── terraform.tfvars.example
└── modules/
    ├── networking/         # VPC, Subnets, IGW, NAT, Routes
    ├── eks/                # Cluster EKS + Node Group + IAM
    ├── rds/                # 3x PostgreSQL
    ├── elasticache/        # Redis cluster
    ├── dynamodb/           # Tabela ToggleMasterAnalytics
    ├── sqs/                # Fila de eventos
    └── ecr/                # 5 repositórios de imagens
```

---

## Troubleshooting

**Terraform init falha com erro de bucket:**
→ Verifique se criou o bucket S3 (Etapa 1) e se o nome está correto no `main.tf`

**EKS nodes não aparecem:**
→ Aguarde ~5 min após apply. Verifique: `kubectl get nodes`

**ArgoCD não sincroniza:**
→ Verifique se o repo gitops é público ou se configurou credenciais no ArgoCD:
```bash
argocd repo add https://github.com/<user>/togglemaster-gitops.git --username <user> --password <PAT>
```

**Pods em CrashLoopBackOff:**
→ Provavelmente ConfigMaps com valores placeholder. Atualize com outputs reais do Terraform.
