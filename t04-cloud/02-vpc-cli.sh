#!/usr/bin/env bash
# T04 - 02-networking / Lab 2: la VPC completa desde la CLI
# Crea VPC -> subnets -> IGW -> route table -> SG -> EC2
# Guarda los IDs en ids-vpc.env para poder limpiar despues.
#
#   bash 02-vpc-cli.sh            -> crea
#   bash 02-vpc-cli.sh limpiar    -> borra (usa ids-vpc.env)
set -euo pipefail

REGION="us-east-1"
KEY_NAME="lab-t04-key"
IDS_FILE="$(dirname "$0")/ids-vpc.env"

if [ "${1:-}" = "limpiar" ]; then
    [ -f "$IDS_FILE" ] || { echo "No existe $IDS_FILE"; exit 1; }
    # shellcheck disable=SC1090
    source "$IDS_FILE"
    echo "== Terminando instancia"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null || true
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION" || true
    echo "== Desasociando y borrando IGW"
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION" || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION" || true
    echo "== Borrando subnets, route table, SG y VPC"
    aws ec2 delete-subnet --subnet-id "$SUBNET_A" --region "$REGION" || true
    aws ec2 delete-subnet --subnet-id "$SUBNET_B" --region "$REGION" || true
    aws ec2 delete-route-table --route-table-id "$RTB_ID" --region "$REGION" || true
    aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" || true
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" || true
    rm -f "$IDS_FILE"
    echo "Limpieza terminada"
    exit 0
fi

echo "== 1. VPC 10.0.0.0/16"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region "$REGION" \
  --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value=lab-t04-vpc --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$REGION"
echo "VPC: $VPC_ID"

echo "== 2. Subnets, una por AZ"
SUBNET_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a --region "$REGION" --query 'Subnet.SubnetId' --output text)
SUBNET_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b --region "$REGION" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_A" --map-public-ip-on-launch --region "$REGION"
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_B" --map-public-ip-on-launch --region "$REGION"
echo "Subnets: $SUBNET_A (1a) / $SUBNET_B (1b)"

echo "== 3. Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
echo "IGW: $IGW_ID"

echo "== 4. Route table con salida a internet"
RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" --region "$REGION" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_A" --region "$REGION" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_B" --region "$REGION" >/dev/null
echo "Route table: $RTB_ID"

echo "== 5. Security Group (SSH desde tu IP, HTTP abierto)"
SG_ID=$(aws ec2 create-security-group --group-name lab-t04-vpc-sg \
  --description "SSH y HTTP para el lab de VPC" --vpc-id "$VPC_ID" \
  --region "$REGION" --query 'GroupId' --output text)
MI_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 \
  --cidr "$MI_IP/32" --region "$REGION" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 \
  --cidr 0.0.0.0/0 --region "$REGION" >/dev/null
echo "SG: $SG_ID"

echo "== 6. Instancia EC2 dentro de la VPC nueva"
AMI=$(aws ec2 describe-images --owners amazon --region "$REGION" \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI" --count 1 --instance-type t3.micro \
  --key-name "$KEY_NAME" --security-group-ids "$SG_ID" --subnet-id "$SUBNET_A" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-t04-vpc-instance}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "Instancia: $INSTANCE_ID"

cat > "$IDS_FILE" <<EOF
VPC_ID=$VPC_ID
SUBNET_A=$SUBNET_A
SUBNET_B=$SUBNET_B
IGW_ID=$IGW_ID
RTB_ID=$RTB_ID
SG_ID=$SG_ID
INSTANCE_ID=$INSTANCE_ID
EOF

echo ""
echo "IDs guardados en $IDS_FILE"
echo "Verificar:   aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --output table"
echo "Al terminar: bash 02-vpc-cli.sh limpiar"
