# ToggleMaster - GitOps

Esse repo guarda os manifestos Kubernetes e a config do ArgoCD do ToggleMaster.

A ideia é simples: o CI dos microsserviços builda a imagem, manda pro ECR e atualiza a tag aqui. O ArgoCD fica de olho nesse repo e aplica qualquer mudança direto no cluster.

## Organização

```
.
├── base/                  # namespace, configmaps, secrets
├── apps/
│   ├── auth-service/      # Go, porta 8001
│   ├── flag-service/      # Python, porta 8002
│   ├── targeting-service/ # Python, porta 8003
│   ├── evaluation-service/# Go, porta 8004
│   └── analytics-service/ # Python, porta 8005
└── argocd/
    ├── applications.yaml  # as 5 apps do ArgoCD
    └── install-argocd.sh  # script pra instalar o ArgoCD no cluster
```

Cada pasta em `apps/` tem um `deployment.yaml` e um `service.yaml`.

## Fluxo de deploy

O deploy funciona assim:

Dev faz push num microsserviço → GitHub Actions roda os testes e scans → builda a imagem e manda pro ECR → atualiza a tag no deployment.yaml desse repo → ArgoCD percebe a mudança e faz o deploy no EKS.

Ninguém faz deploy manual. Tudo passa pelo Git.

## Infra por trás

A infra toda tá no repo `togglemaster-infra` e foi criada com Terraform:

- VPC com subnets públicas e privadas em 2 AZs
- EKS com 2 nodes t3.medium nas subnets privadas
- 3 instâncias RDS PostgreSQL (uma por serviço que usa banco)
- ElastiCache Redis
- DynamoDB (tabela ToggleMasterAnalytics)
- SQS pra fila de eventos
- 5 repos no ECR

## Como subir do zero

Precisa de: AWS CLI, Terraform, kubectl e git.

**Criar o bucket pro state do Terraform:**

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket togglemaster-tfstate-${ACCOUNT_ID} --region us-east-1
aws s3api put-bucket-versioning --bucket togglemaster-tfstate-${ACCOUNT_ID} --versioning-configuration Status=Enabled
```

**Rodar o Terraform:**

```bash
cd togglemaster-infra
cp terraform.tfvars.example terraform.tfvars
# edita o tfvars com a senha do banco e o main.tf com o nome do bucket
terraform init && terraform apply
```

**Conectar no cluster e instalar ArgoCD:**

```bash
aws eks update-kubeconfig --name togglemaster-prod-eks --region us-east-1
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

**Aplicar os manifestos e registrar as apps:**

```bash
kubectl apply -f base/
kubectl apply -f argocd/applications.yaml
```

A senha do ArgoCD pega com:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**CI nos microsserviços:**

Cada repo precisa de `.github/workflows/ci.yml` e 3 secrets configurados: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `GITOPS_PAT`.

## Pra derrubar tudo

```bash
kubectl delete -f argocd/applications.yaml
kubectl delete namespace togglemaster
kubectl delete namespace argocd
cd togglemaster-infra && terraform destroy
aws s3 rb s3://togglemaster-tfstate-<ACCOUNT_ID> --force
```
