#!/usr/bin/env bash
# T06 lab 2, pasos 02 y 03: cluster Fargate y cluster EC2-Linux
set -e
. "$HOME/practica/t06/comun.sh"; cargar

echo "== 02: cluster Fargate 'fargate-demo' con Container Insights =="
aws ecs create-cluster --cluster-name fargate-demo $R \
  --settings name=containerInsights,value=enabled \
  --query 'cluster.[clusterName,status]' --output text

echo ""
echo "== 03: cluster EC2-Linux 'ecs-ec2-demo' =="
aws ecs create-cluster --cluster-name ecs-ec2-demo $R \
  --settings name=containerInsights,value=enabled \
  --query 'cluster.[clusterName,status]' --output text

echo "-- key pair ecs-fnotte"
if ! aws ec2 describe-key-pairs --key-names ecs-fnotte $R >/dev/null 2>&1; then
  aws ec2 create-key-pair --key-name ecs-fnotte $R --query KeyMaterial --output text > "$HOME/ecs-fnotte.pem"
  chmod 400 "$HOME/ecs-fnotte.pem"
  echo "   creada, clave privada en ~/ecs-fnotte.pem"
else
  echo "   ya existia"
fi

echo "-- AMI optimizada para ECS"
AMI=$(aws ssm get-parameters $R --names /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id --query 'Parameters[0].Value' --output text)
echo "   $AMI"

echo "-- security group de las instancias del cluster"
SG_EC2=$(aws ec2 describe-security-groups $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=ecs-ec2-instances" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_EC2" = "None" ]; then
  SG_EC2=$(aws ec2 create-security-group --group-name ecs-ec2-instances --description "Instancias del cluster ECS EC2" --vpc-id "$VPC_ID" $R --query GroupId --output text)
  # el ALB entra por puertos efimeros al host (bridge mode): se abre el rango completo dentro de la VPC
  aws ec2 authorize-security-group-ingress --group-id "$SG_EC2" --protocol tcp --port 0-65535 --cidr 10.0.0.0/16 $R >/dev/null
  MI_IP=$(curl -s https://checkip.amazonaws.com)
  aws ec2 authorize-security-group-ingress --group-id "$SG_EC2" --protocol tcp --port 22 --cidr "$MI_IP/32" $R >/dev/null
fi
echo "   $SG_EC2"; guardar SG_EC2 "$SG_EC2"

echo "-- launch template con el agente de ECS apuntando al cluster"
UD=$(printf '#!/bin/bash\necho ECS_CLUSTER=ecs-ec2-demo >> /etc/ecs/ecs.config\n' | base64 -w0)
aws ec2 delete-launch-template --launch-template-name ecs-ec2-lt $R >/dev/null 2>&1 || true
LT=$(aws ec2 create-launch-template --launch-template-name ecs-ec2-lt $R \
  --launch-template-data "{\"ImageId\":\"$AMI\",\"InstanceType\":\"t3.small\",\"KeyName\":\"ecs-fnotte\",\"SecurityGroupIds\":[\"$SG_EC2\"],\"IamInstanceProfile\":{\"Name\":\"LabInstanceProfile\"},\"UserData\":\"$UD\"}" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
echo "   $LT"; guardar LT "$LT"

echo "-- auto scaling group con 1 instancia"
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name ecs-ec2-asg --force-delete $R >/dev/null 2>&1 || true
sleep 5
aws autoscaling create-auto-scaling-group --auto-scaling-group-name ecs-ec2-asg $R \
  --launch-template "LaunchTemplateId=$LT,Version=\$Latest" \
  --min-size 1 --max-size 2 --desired-capacity 1 \
  --vpc-zone-identifier "$SUB1,$SUB2"
echo "   ecs-ec2-asg creado"

echo "-- esperando a que la instancia se registre en el cluster"
for i in $(seq 1 30); do
  N=$(aws ecs describe-clusters --clusters ecs-ec2-demo $R --query 'clusters[0].registeredContainerInstancesCount' --output text)
  echo "   [$i] instancias registradas: $N"
  [ "$N" != "0" ] && break
  sleep 20
done

echo ""
echo "== Estado de los dos clusters =="
aws ecs describe-clusters --clusters fargate-demo ecs-ec2-demo $R \
  --query 'clusters[].{Cluster:clusterName,Estado:status,Instancias:registeredContainerInstancesCount,Services:activeServicesCount}' --output table
