#!/usr/bin/env bash
# T04 - 01-IaaS / Lab 5: el ejercicio de la AWS CLI, resuelto
#   crear instancia "instancia-desde-cli" (t2.micro) + SG con el puerto 80,
#   buscarla por su tag Name, y terminarla.
#
#   bash 10-instancia-desde-cli.sh           -> crea
#   bash 10-instancia-desde-cli.sh buscar    -> la busca por tag, como pide el lab
#   bash 10-instancia-desde-cli.sh limpiar   -> termina la instancia y borra el SG
set -euo pipefail

REGION="us-east-1"
NOMBRE="instancia-desde-cli"
SG_NAME="puerto-80"
KEY_NAME="${KEY_NAME:-vockey}"   # el Learner Lab ya trae vockey

buscar_por_tag() {
    aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag:Name,Values=$NOMBRE" "Name=instance-state-name,Values=pending,running,stopped" \
      --query 'Reservations[].Instances[].{ID:InstanceId,Estado:State.Name,IP:PublicIpAddress,Tipo:InstanceType}' \
      --output table
}

case "${1:-crear}" in

buscar)
    buscar_por_tag
    ;;

crear)
    # El AMI fijo del lab (ami-0533f2ba8a1995cf9) ya caduco: se busca el vigente.
    echo "== Buscando el AMI actual de Amazon Linux 2"
    AMI=$(aws ec2 describe-images --owners amazon --region "$REGION" \
      --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
      --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
    echo "   AMI: $AMI"

    VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" \
      --query 'Vpcs[0].VpcId' --output text)

    echo "== Security Group con el puerto 80 abierto"
    SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" \
      --description "HTTP desde internet" --vpc-id "$VPC_ID" --region "$REGION" \
      --query 'GroupId' --output text 2>/dev/null \
      || aws ec2 describe-security-groups --group-names "$SG_NAME" --region "$REGION" \
           --query 'SecurityGroups[0].GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 \
      --cidr 0.0.0.0/0 --region "$REGION" >/dev/null 2>&1 || true
    echo "   SG: $SG_ID"

    echo "== Lanzando la instancia"
    ID=$(aws ec2 run-instances --region "$REGION" \
      --image-id "$AMI" --count 1 --instance-type t2.micro \
      --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NOMBRE}]" \
      --query 'Instances[0].InstanceId' --output text)
    aws ec2 wait instance-running --instance-ids "$ID" --region "$REGION"

    echo ""
    echo "La instancia, buscada por su tag Name (lo que pide el lab):"
    buscar_por_tag
    echo ""
    echo "Al terminar: bash 10-instancia-desde-cli.sh limpiar"
    ;;

limpiar)
    IDS=$(aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag:Name,Values=$NOMBRE" "Name=instance-state-name,Values=pending,running,stopped" \
      --query 'Reservations[].Instances[].InstanceId' --output text)
    if [ -n "$IDS" ]; then
        aws ec2 terminate-instances --instance-ids $IDS --region "$REGION" >/dev/null
        echo "Esperando a que termine (el SG no se puede borrar antes)..."
        aws ec2 wait instance-terminated --instance-ids $IDS --region "$REGION"
    fi
    aws ec2 delete-security-group --group-name "$SG_NAME" --region "$REGION" 2>/dev/null || true
    echo "Limpieza terminada"
    ;;
esac
