#!/bin/bash


set -e

echo "=========================================="
echo "  Instalando ArgoCD no cluster EKS"
echo "=========================================="


kubectl create namespace argocd 2>/dev/null || echo "Namespace argocd já existe"


echo "Instalando ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


echo "Aguardando ArgoCD ficar pronto..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd


kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'


echo ""
echo " Sucesso!"
echo ""
echo "Senha admin:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "URL do ArgoCD:"
kubectl get svc argocd-server -n argocd -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo ""
echo ""
echo "Aplicattions...:"
echo "  kubectl apply -f argocd/applications.yaml"
