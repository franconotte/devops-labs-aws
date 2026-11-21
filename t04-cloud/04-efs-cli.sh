#!/usr/bin/env bash
# T04 - 03-storage / Lab 3: EFS desde la CLI
# Crea el file system, un mount target por AZ y muestra como montarlo.
# Requiere: las dos instancias del lab 01 corriendo (o indicar SUBNET_A/SUBNET_B).
#
#   bash 04-efs-cli.sh
#   bash 04-efs-cli.sh limpiar
set -euo pipefail

REGION="us-east-1"
IDS_FILE="$(dirname "$0")/ids-efs.env"

if [ "${1:-}" = "limpiar" ]; then
    [ -f "$IDS_FILE" ] || { echo "No existe $IDS_FILE"; exit 1; }
    # shellcheck disable=SC1090
    source "$IDS_FILE"
    echo "== Borrando mount targets"
    for MT in $(aws efs describe-mount-targets --file-system-id "$FS_ID" --region "$REGION" \
                 --query 'MountTargets[].MountTargetId' --output text); do
        aws efs delete-mount-target --mount-target-id "$MT" --region "$REGION"
    done
    echo "   esperando a que desaparezcan..."
    while [ "$(aws efs describe-mount-targets --file-system-id "$FS_ID" --region "$REGION" \
              --query 'length(MountTargets)' --output text)" != "0" ]; do sleep 5; done
    aws efs delete-file-system --file-system-id "$FS_ID" --region "$REGION"
    aws ec2 delete-security-group --group-id "$SG_EFS" --region "$REGION" || true
    rm -f "$IDS_FILE"
    echo "Limpieza terminada"
    exit 0
fi

VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text)

echo "== Security Group para NFS (puerto 2049)"
SG_EFS=$(aws ec2 create-security-group --group-name lab-t04-efs \
  --description "NFS para EFS" --vpc-id "$VPC_ID" --region "$REGION" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_EFS" --protocol tcp --port 2049 \
  --cidr 172.31.0.0/16 --region "$REGION" >/dev/null
echo "SG EFS: $SG_EFS"

echo "== Creando el file system"
FS_ID=$(aws efs create-file-system --performance-mode generalPurpose \
  --tags Key=Name,Value=lab-t04-efs --region "$REGION" \
  --query 'FileSystemId' --output text)
echo "FileSystemId: $FS_ID"

echo "== Esperando a que quede available"
while [ "$(aws efs describe-file-systems --file-system-id "$FS_ID" --region "$REGION" \
          --query 'FileSystems[0].LifeCycleState' --output text)" != "available" ]; do
    sleep 5
done
echo "   available"

echo "== Mount target en cada AZ"
for AZ in us-east-1a us-east-1b; do
    SUBNET=$(aws ec2 describe-subnets --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$AZ" \
      --query 'Subnets[0].SubnetId' --output text)
    aws efs create-mount-target --file-system-id "$FS_ID" --subnet-id "$SUBNET" \
      --security-groups "$SG_EFS" --region "$REGION" \
      --query 'MountTargetId' --output text
done

printf 'FS_ID=%s\nSG_EFS=%s\n' "$FS_ID" "$SG_EFS" > "$IDS_FILE"

echo ""
echo "Dentro de CADA instancia EC2, para montarlo:"
echo "  sudo dnf install -y amazon-efs-utils    # Amazon Linux"
echo "  sudo mkdir -p /mnt/efs"
echo "  sudo mount -t efs $FS_ID:/ /mnt/efs"
echo "  df -h | grep efs"
echo ""
echo "Prueba del lab: crear un archivo desde una instancia y verlo desde la otra."
echo "  instancia 1:  sudo touch /mnt/efs/hola-desde-la-1"
echo "  instancia 2:  ls -l /mnt/efs"
echo ""
echo "Al terminar: bash 04-efs-cli.sh limpiar"
