#!/usr/bin/env bash
# T06 lab 2, paso 01: la VPC que piden los labs (10.0.0.0/16, subnets publicas)
set -e
. "$HOME/practica/t06/comun.sh"
touch "$IDS"; cargar

echo "== VPC 10.0.0.0/16 =="
VPC_ID=$(aws ec2 describe-vpcs $R --filters "Name=tag:Name,Values=ecs-vpc" --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" = "None" ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 $R --query 'Vpc.VpcId' --output text)
  aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value=ecs-vpc $R
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames $R
fi
echo "   VPC: $VPC_ID"; guardar VPC_ID "$VPC_ID"

crear_subnet() {
  local cidr=$1 az=$2 nombre=$3 id
  id=$(aws ec2 describe-subnets $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$nombre" --query 'Subnets[0].SubnetId' --output text)
  if [ "$id" = "None" ]; then
    id=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$az" $R --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources "$id" --tags Key=Name,Value="$nombre" $R
    aws ec2 modify-subnet-attribute --subnet-id "$id" --map-public-ip-on-launch $R
  fi
  echo "$id"
}
echo "== Subnets publicas en dos AZ (el ALB las exige) =="
SUB1=$(crear_subnet 10.0.1.0/24 ${REGION}a ecs-publica-1a)
SUB2=$(crear_subnet 10.0.2.0/24 ${REGION}b ecs-publica-1b)
echo "   $SUB1 / $SUB2"; guardar SUB1 "$SUB1"; guardar SUB2 "$SUB2"

echo "== Internet Gateway y route table =="
IGW=$(aws ec2 describe-internet-gateways $R --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)
if [ "$IGW" = "None" ]; then
  IGW=$(aws ec2 create-internet-gateway $R --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" $R
fi
RTB=$(aws ec2 describe-route-tables $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=ecs-rtb-publica" --query 'RouteTables[0].RouteTableId' --output text)
if [ "$RTB" = "None" ]; then
  RTB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" $R --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-tags --resources "$RTB" --tags Key=Name,Value=ecs-rtb-publica $R
  aws ec2 create-route --route-table-id "$RTB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" $R >/dev/null
  aws ec2 associate-route-table --route-table-id "$RTB" --subnet-id "$SUB1" $R >/dev/null
  aws ec2 associate-route-table --route-table-id "$RTB" --subnet-id "$SUB2" $R >/dev/null
fi
echo "   IGW: $IGW   RTB: $RTB"; guardar IGW "$IGW"; guardar RTB "$RTB"

echo "== Security group ecs-nginx (puerto 80) =="
SG_NGINX=$(aws ec2 describe-security-groups $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=ecs-nginx" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_NGINX" = "None" ]; then
  SG_NGINX=$(aws ec2 create-security-group --group-name ecs-nginx --description "HTTP para las tasks de ECS" --vpc-id "$VPC_ID" $R --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG_NGINX" --protocol tcp --port 80 --cidr 0.0.0.0/0 $R >/dev/null
fi
echo "   SG: $SG_NGINX"; guardar SG_NGINX "$SG_NGINX"
echo ""; echo "Red lista."; cat "$IDS"
