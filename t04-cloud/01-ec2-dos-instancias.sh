#!/usr/bin/env bash
# T04 - 01-IaaS / Lab 1: dos instancias EC2 en distintas zonas de disponibilidad
#
#   bash 01-ec2-dos-instancias.sh           -> crea todo
#   bash 01-ec2-dos-instancias.sh limpiar   -> borra todo
set -euo pipefail

REGION="us-east-1"
KEY_NAME="lab-t04-key"
SG_NAME="lab-t04-ssh"
NOMBRE_TAG="Name=tag:Name,Values=test-instance01,test-instance02"

limpiar() {
    echo "== Terminando instancias"
    IDS=$(aws ec2 describe-instances --region "$REGION" \
      --filters "$NOMBRE_TAG" "Name=instance-state-name,Values=running,pending,stopped" \
      --query 'Reservations[].Instances[].InstanceId' --output text)
    if [ -n "$IDS" ]; then
        aws ec2 terminate-instances --instance-ids $IDS --region "$REGION" >/dev/null
        aws ec2 wait instance-terminated --instance-ids $IDS --region "$REGION"
    fi
    aws ec2 delete-security-group --group-name "$SG_NAME" --region "$REGION" 2>/dev/null || true
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION" 2>/dev/null || true
    rm -f "$HOME/$KEY_NAME.pem"
    echo "Limpieza terminada"
}

if [ "${1:-}" = "limpiar" ]; then
    limpiar
    exit 0
fi

echo "== Buscando la AMI de Amazon Linux mas reciente"
AMI=$(aws ec2 describe-images --owners amazon --region "$REGION" \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)
echo "AMI: $AMI"

echo "== Key pair"
if [ ! -f "$HOME/$KEY_NAME.pem" ]; then
    aws ec2 create-key-pair --key-name "$KEY_NAME" --region "$REGION" \
      --query 'KeyMaterial' --output text > "$HOME/$KEY_NAME.pem"
    chmod 400 "$HOME/$KEY_NAME.pem"
    echo "Clave privada en ~/$KEY_NAME.pem"
else
    echo "Ya existe ~/$KEY_NAME.pem"
fi

echo "== Security Group (SSH solo desde tu IP)"
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" \
  --description "SSH para el lab T04" --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text --region "$REGION")
MI_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "$MI_IP/32" --region "$REGION" >/dev/null
echo "SG: $SG_ID  (22/tcp desde $MI_IP)"

echo "== Subnets de us-east-1a y us-east-1b"
SUBNET_A=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-east-1a" \
  --query 'Subnets[0].SubnetId' --output text)
SUBNET_B=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-east-1b" \
  --query 'Subnets[0].SubnetId' --output text)

lanzar() {
    local nombre="$1" subnet="$2"
    echo "== Lanzando $nombre"
    aws ec2 run-instances --region "$REGION" \
      --image-id "$AMI" --count 1 --instance-type t3.micro \
      --key-name "$KEY_NAME" --security-group-ids "$SG_ID" --subnet-id "$subnet" \
      --associate-public-ip-address \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$nombre}]" \
      --query 'Instances[0].InstanceId' --output text
}

lanzar test-instance01 "$SUBNET_A"
lanzar test-instance02 "$SUBNET_B"

echo "== Esperando a que esten running (1-2 minutos)"
aws ec2 wait instance-running --region "$REGION" --filters "$NOMBRE_TAG"

echo "== Datos que pide la seccion 'Para discutir en grupo'"
aws ec2 describe-instances --region "$REGION" \
  --filters "$NOMBRE_TAG" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[0].Value,Placement.AvailabilityZone,PrivateIpAddress,PublicIpAddress]' \
  --output table

echo ""
echo "Conectarse:  ssh -i ~/$KEY_NAME.pem ec2-user@<IP_PUBLICA>"
echo "Probar ping: ping <IP_PRIVADA_DE_LA_OTRA>   (ver preguntas.md)"
echo "Al terminar: bash 01-ec2-dos-instancias.sh limpiar"
