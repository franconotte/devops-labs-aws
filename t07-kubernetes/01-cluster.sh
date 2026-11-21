#!/usr/bin/env bash
# T07 parte 1: kubectl + cluster EKS
set -e
. "$HOME/practica/t07/comun.sh"; touch "$IDS"; cargar

echo "== kubectl =="
if ! command -v kubectl >/dev/null 2>&1; then
  cd /tmp
  curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -m 0755 kubectl "$HOME/.local/bin/kubectl"   # sin sudo: va a ~/.local/bin
fi
kubectl version --client --output=yaml 2>/dev/null | grep gitVersion | head -1

echo "== reuso la VPC del T06 =="
VPC_ID=$(aws ec2 describe-vpcs $R --filters "Name=tag:Name,Values=ecs-vpc" --query 'Vpcs[0].VpcId' --output text)
SUB1=$(aws ec2 describe-subnets $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=ecs-publica-1a" --query 'Subnets[0].SubnetId' --output text)
SUB2=$(aws ec2 describe-subnets $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=ecs-publica-1b" --query 'Subnets[0].SubnetId' --output text)
echo "   $VPC_ID  $SUB1 $SUB2"
guardar VPC_ID "$VPC_ID"; guardar SUB1 "$SUB1"; guardar SUB2 "$SUB2"

# para que los Service type=LoadBalancer sepan donde poner el ELB
aws ec2 create-tags --resources "$SUB1" "$SUB2" --tags Key=kubernetes.io/role/elb,Value=1 $R
echo "   subnets etiquetadas para ELB"

echo "== security group del cluster =="
SG_EKS=$(aws ec2 describe-security-groups $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=eks-cluster-sg" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_EKS" = "None" ]; then
  SG_EKS=$(aws ec2 create-security-group --group-name eks-cluster-sg --description "EKS control plane" --vpc-id "$VPC_ID" $R --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG_EKS" --protocol -1 --cidr 10.0.0.0/16 $R >/dev/null
fi
guardar SG_EKS "$SG_EKS"

echo "== creando el cluster EKS 'eks-cluster' con LabRole (tarda ~12 min) =="
if ! aws eks describe-cluster --name eks-cluster $R >/dev/null 2>&1; then
  aws eks create-cluster --name eks-cluster $R \
    --role-arn "$LABROLE" \
    --resources-vpc-config "subnetIds=$SUB1,$SUB2,securityGroupIds=$SG_EKS,endpointPublicAccess=true,endpointPrivateAccess=true" \
    --query 'cluster.[name,status]' --output text
else
  echo "   ya existia"
fi
for i in $(seq 1 45); do
  EST=$(aws eks describe-cluster --name eks-cluster $R --query 'cluster.status' --output text)
  echo "   [$i] $EST"
  [ "$EST" = "ACTIVE" ] && break
  sleep 30
done
aws eks describe-cluster --name eks-cluster $R --query 'cluster.{Nombre:name,Estado:status,Version:version,Endpoint:endpoint}' --output table
