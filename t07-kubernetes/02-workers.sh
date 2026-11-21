#!/usr/bin/env bash
# T07 parte 2: node group de workers EC2
set -e
. "$HOME/practica/t07/comun.sh"; cargar
echo "== node group con LabRole, 2 nodos t3.medium =="
if ! aws eks describe-nodegroup --cluster-name eks-cluster --nodegroup-name workers $R >/dev/null 2>&1; then
  aws eks create-nodegroup --cluster-name eks-cluster --nodegroup-name workers $R \
    --node-role "$LABROLE" --subnets "$SUB1" "$SUB2" \
    --scaling-config minSize=2,maxSize=3,desiredSize=2 \
    --instance-types t3.medium --ami-type AL2023_x86_64_STANDARD \
    --capacity-type ON_DEMAND --disk-size 20 \
    --query 'nodegroup.[nodegroupName,status]' --output text
fi
for i in $(seq 1 40); do
  EST=$(aws eks describe-nodegroup --cluster-name eks-cluster --nodegroup-name workers $R --query 'nodegroup.status' --output text)
  echo "   [$i] $EST"; [ "$EST" = "ACTIVE" ] && break
  [ "$EST" = "CREATE_FAILED" ] && { aws eks describe-nodegroup --cluster-name eks-cluster --nodegroup-name workers $R --query 'nodegroup.health' --output json; exit 1; }
  sleep 30
done
echo "== kubeconfig =="
aws eks --region us-east-1 update-kubeconfig --name eks-cluster
echo "== nodos =="
kubectl get nodes -o wide
