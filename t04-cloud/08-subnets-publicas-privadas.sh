#!/usr/bin/env bash
# T04 - 02-networking / Lab 3: subnets publicas y privadas con NAT Gateway y bastion
# Arquitectura:
#   publica  10.0.1.0/24 (1a) y 10.0.2.0/24 (1b): bastion + NAT Gateway
#   privada  10.0.3.0/24 (1a) y 10.0.4.0/24 (1b): instancia sin IP publica
#
#   bash 08-subnets-publicas-privadas.sh          -> crea
#   bash 08-subnets-publicas-privadas.sh limpiar  -> borra en el orden correcto
set -euo pipefail

REGION="us-east-1"
KEY_NAME="lab-t04-key"
IDS_FILE="$(dirname "$0")/ids-redes.env"

if [ "${1:-}" = "limpiar" ]; then
    [ -f "$IDS_FILE" ] || { echo "No existe $IDS_FILE"; exit 1; }
    # shellcheck disable=SC1090
    source "$IDS_FILE"
    echo "== Terminando instancias"
    aws ec2 terminate-instances --instance-ids $BASTION $PRIVADA --region "$REGION" >/dev/null || true
    aws ec2 wait instance-terminated --instance-ids $BASTION $PRIVADA --region "$REGION" || true
    echo "== Borrando NAT Gateway (tarda ~2 min) y liberando la Elastic IP"
    aws ec2 delete-nat-gateway --nat-gateway-id "$NATGW" --region "$REGION" >/dev/null || true
    while [ "$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NATGW" --region "$REGION" --query 'NatGateways[0].State' --output text 2>/dev/null)" != "deleted" ]; do sleep 10; done
    aws ec2 release-address --allocation-id "$EIP_ALLOC" --region "$REGION" || true
    echo "== Borrando red"
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region "$REGION" || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$REGION" || true
    for s in $SUB_PUB1 $SUB_PUB2 $SUB_PRIV1 $SUB_PRIV2; do
        aws ec2 delete-subnet --subnet-id "$s" --region "$REGION" || true
    done
    aws ec2 delete-route-table --route-table-id "$RTB_PUB" --region "$REGION" || true
    aws ec2 delete-route-table --route-table-id "$RTB_PRIV" --region "$REGION" || true
    aws ec2 delete-security-group --group-id "$SG_PRIV" --region "$REGION" || true
    aws ec2 delete-security-group --group-id "$SG_PUB" --region "$REGION" || true
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" || true
    rm -f "$IDS_FILE"
    echo "Limpieza terminada"
    exit 0
fi

echo "== VPC"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region "$REGION" --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value=lab-t04-redes --region "$REGION"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$REGION"

crear_subnet() {
    local cidr="$1" az="$2" nombre="$3" publica="$4"
    local id
    id=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$az" \
      --region "$REGION" --query 'Subnet.SubnetId' --output text)
    aws ec2 create-tags --resources "$id" --tags Key=Name,Value="$nombre" --region "$REGION"
    [ "$publica" = "si" ] && aws ec2 modify-subnet-attribute --subnet-id "$id" --map-public-ip-on-launch --region "$REGION"
    echo "$id"
}

echo "== Subnets"
SUB_PUB1=$(crear_subnet 10.0.1.0/24 us-east-1a publica-1a si)
SUB_PUB2=$(crear_subnet 10.0.2.0/24 us-east-1b publica-1b si)
SUB_PRIV1=$(crear_subnet 10.0.3.0/24 us-east-1a privada-1a no)
SUB_PRIV2=$(crear_subnet 10.0.4.0/24 us-east-1b privada-1b no)

echo "== Internet Gateway y route table publica"
IGW=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region "$REGION"
RTB_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" --region "$REGION" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PUB" --subnet-id "$SUB_PUB1" --region "$REGION" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PUB" --subnet-id "$SUB_PUB2" --region "$REGION" >/dev/null

echo "== Elastic IP + NAT Gateway (tarda ~2 min)"
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --region "$REGION" --query 'AllocationId' --output text)
NATGW=$(aws ec2 create-nat-gateway --subnet-id "$SUB_PUB1" --allocation-id "$EIP_ALLOC" \
  --region "$REGION" --query 'NatGateway.NatGatewayId' --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NATGW" --region "$REGION"

echo "== Route table privada, salida por el NAT"
RTB_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PRIV" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NATGW" --region "$REGION" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PRIV" --subnet-id "$SUB_PRIV1" --region "$REGION" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PRIV" --subnet-id "$SUB_PRIV2" --region "$REGION" >/dev/null

echo "== Security Groups"
MI_IP=$(curl -s https://checkip.amazonaws.com)
SG_PUB=$(aws ec2 create-security-group --group-name lab-t04-bastion --description "SSH al bastion" \
  --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_PUB" --protocol tcp --port 22 --cidr "$MI_IP/32" --region "$REGION" >/dev/null
SG_PRIV=$(aws ec2 create-security-group --group-name lab-t04-privada --description "SSH solo desde el bastion" \
  --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_PRIV" --protocol tcp --port 22 --source-group "$SG_PUB" --region "$REGION" >/dev/null

AMI=$(aws ec2 describe-images --owners amazon --region "$REGION" \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)

echo "== Bastion en la subnet publica"
BASTION=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" --count 1 --instance-type t3.micro \
  --key-name "$KEY_NAME" --security-group-ids "$SG_PUB" --subnet-id "$SUB_PUB1" --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "== Instancia en la subnet privada (sin IP publica)"
PRIVADA=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" --count 1 --instance-type t3.micro \
  --key-name "$KEY_NAME" --security-group-ids "$SG_PRIV" --subnet-id "$SUB_PRIV1" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=app-privada}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids "$BASTION" "$PRIVADA" --region "$REGION"
IP_BASTION=$(aws ec2 describe-instances --instance-ids "$BASTION" --region "$REGION" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
IP_PRIVADA=$(aws ec2 describe-instances --instance-ids "$PRIVADA" --region "$REGION" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

cat > "$IDS_FILE" <<EOF
VPC_ID=$VPC_ID
SUB_PUB1=$SUB_PUB1
SUB_PUB2=$SUB_PUB2
SUB_PRIV1=$SUB_PRIV1
SUB_PRIV2=$SUB_PRIV2
IGW=$IGW
RTB_PUB=$RTB_PUB
RTB_PRIV=$RTB_PRIV
NATGW=$NATGW
EIP_ALLOC=$EIP_ALLOC
SG_PUB=$SG_PUB
SG_PRIV=$SG_PRIV
BASTION=$BASTION
PRIVADA=$PRIVADA
EOF

echo ""
echo "Bastion:  ssh -i ~/$KEY_NAME.pem ec2-user@$IP_BASTION"
echo "Privada:  desde el bastion -> ssh ec2-user@$IP_PRIVADA"
echo "   (o directo con salto:  ssh -i ~/$KEY_NAME.pem -J ec2-user@$IP_BASTION ec2-user@$IP_PRIVADA)"
echo ""
echo "Prueba del NAT: dentro de la instancia privada, 'curl -s https://checkip.amazonaws.com'"
echo "   responde la IP del NAT Gateway, no la de la instancia."
echo ""
echo "⚠️  El NAT Gateway consume creditos por hora aunque no lo uses."
echo "Al terminar: bash 08-subnets-publicas-privadas.sh limpiar"
