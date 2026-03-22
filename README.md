# ToggleMaster - GitOps

Repositório de manifestos Kubernetes e configuração do ArgoCD pro ToggleMaster.

O ArgoCD monitora esse repositório e sincroniza qualquer mudança automaticamente no cluster EKS. Quando o CI de um microsserviço faz push de uma imagem nova pro ECR, ele atualiza a tag aqui e o ArgoCD faz o deploy.

## Estrutura

```
.
├── base/                  # namespace, configmaps e secrets
├── apps/
│   ├── auth-service/      # deployment + service (Go, porta 8001)
│   ├── flag-service/      # deployment + service (Python, porta 8002)
│   ├── targeting-service/ # deployment + service (Python, porta 8003)
│   ├── evaluation-service/# deployment + service (Go, porta 8004)
│   └── analytics-service/ # deployment + service (Python, porta 8005)
└── argocd/
    ├── applications.yaml  # definição das 5 Applications do ArgoCD
    └── install-argocd.sh  # script de instalação do ArgoCD
```

## Como funciona o fluxo

1. Dev faz push no repo de um microsserviço
2. GitHub Actions roda build, testes, lint, scan de segurança
3. Se passou, builda a imagem Docker e envia pro ECR
4. O último step do CI atualiza o `deployment.yaml` aqui nesse repo com a nova tag
5. ArgoCD detecta a mudança e faz o deploy no EKS automaticamente

## Arquitetura na AWS

```
GitHub Actions (CI)  ── push imagem ──>  ECR
                     ── atualiza tag ──> este repo
ArgoCD (CD)          ── monitora ──>     este repo  ── sync ──> EKS
```

Recursos provisionados via Terraform (repo `togglemaster-infra`):

- VPC com subnets públicas e privadas
- EKS com 2 nodes (t3.medium)
- 3x RDS PostgreSQL (auth, flag, targeting)
- ElastiCache Redis (targeting, evaluation)
- DynamoDB - tabela ToggleMasterAnalytics
- SQS - fila de eventos de avaliação
- ECR - 5 repositórios de imagens

## Setup inicial

Pré-requisitos: AWS CLI, Terraform, kubectl, git.

### 1. Infra (Terraform)

Criar o bucket S3 pro state remoto e rodar o Terraform:

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket togglemaster-tfstate-${ACCOUNT_ID} --region us-east-1
aws s3api put-bucket-versioning --bucket togglemaster-tfstate-${ACCOUNT_ID} --versioning-configuration Status=Enabled
```

```bash
cd togglemaster-infra
cp terraform.tfvars.example terraform.tfvars
# editar terraform.tfvars com a senha do banco
# editar main.tf com o nome do bucket S3
terraform init && terraform apply
```

### 2. Conectar no cluster

```bash
aws eks update-kubeconfig --name togglemaster-prod-eks --region us-east-1
kubectl get nodes
```

### 3. Instalar ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# pegar a senha
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 4. Aplicar manifestos

```bash
kubectl apply -f base/
kubectl apply -f argocd/applications.yaml
```

### 5. Configurar CI nos microsserviços

Cada repo precisa de um `.github/workflows/ci.yml` e dos secrets configurados:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`  
- `GITOPS_PAT`

## Limpeza

Depois de entregar o projeto, destruir tudo pra não gerar custo:

```bash
kubectl delete -f argocd/applications.yaml
cd togglemaster-infra && terraform destroy
aws s3 rb s3://togglemaster-tfstate-<ACCOUNT_ID> --force
```
