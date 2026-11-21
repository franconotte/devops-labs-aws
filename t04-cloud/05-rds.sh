#!/usr/bin/env bash
# T04 - 04-RDS: instancia MySQL gestionada + acceso desde EC2
#
#   bash 05-rds.sh crear     -> crea el SG y la instancia RDS (pide la password por teclado)
#   bash 05-rds.sh estado    -> muestra estado y endpoint
#   bash 05-rds.sh limpiar   -> borra la instancia y el SG
set -euo pipefail

REGION="us-east-1"
DB_ID="my-dbinstance"
SG_NAME="lab-t04-rds"
USUARIO="admin"

case "${1:-crear}" in
crear)
    VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" \
      --query 'Vpcs[0].VpcId' --output text)

    echo "== Security Group para MySQL (3306)"
    SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" \
      --description "MySQL para el lab T04" --vpc-id "$VPC_ID" --region "$REGION" \
      --query 'GroupId' --output text 2>/dev/null \
      || aws ec2 describe-security-groups --region "$REGION" \
           --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$SG_NAME" \
           --query 'SecurityGroups[0].GroupId' --output text)
    # Lo correcto es permitir 3306 SOLO desde el SG de las instancias EC2:
    SG_EC2=$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=group-name,Values=lab-t04-ssh" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    if [ -n "$SG_EC2" ] && [ "$SG_EC2" != "None" ]; then
        aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 3306 \
          --source-group "$SG_EC2" --region "$REGION" >/dev/null 2>&1 || true
        echo "3306 permitido desde el SG de las EC2 ($SG_EC2)"
    else
        echo "No encontre el SG lab-t04-ssh: abri el 3306 a mano cuando tengas la EC2"
    fi

    echo ""
    echo "Ingresa la password del usuario '$USUARIO' (no se muestra ni queda en el historial):"
    read -r -s DB_PASS
    echo ""

    echo "== Creando la instancia RDS (tarda ~5 minutos)"
    aws rds create-db-instance --region "$REGION" \
      --db-instance-identifier "$DB_ID" \
      --db-instance-class db.t3.micro \
      --engine mysql \
      --master-username "$USUARIO" \
      --master-user-password "$DB_PASS" \
      --allocated-storage 20 \
      --no-publicly-accessible \
      --no-multi-az \
      --vpc-security-group-ids "$SG_ID" \
      --backup-retention-period 0 \
      --query 'DBInstance.DBInstanceIdentifier' --output text
    unset DB_PASS

    echo "== Esperando a que quede available"
    aws rds wait db-instance-available --db-instance-identifier "$DB_ID" --region "$REGION"
    bash "$0" estado
    ;;

estado)
    aws rds describe-db-instances --db-instance-identifier "$DB_ID" --region "$REGION" \
      --query 'DBInstances[0].[DBInstanceStatus,Engine,Endpoint.Address,Endpoint.Port]' \
      --output table
    echo ""
    echo "Desde una instancia EC2 de la misma VPC:"
    echo "  sudo dnf install -y mariadb105            # Amazon Linux"
    echo "  mysql -h <endpoint> -u $USUARIO -p"
    echo "  show databases; create database dbtest; use dbtest;"
    echo ""
    echo "Importar el dump de ejemplo:"
    echo "  curl -O https://gist.githubusercontent.com/mauricioamendola/d72a811b62129a4af16d6623ae32ed54/raw/d1cfd290385b52c4142a67bd230e793dcb258a5f/simple-mysql-dump"
    echo "  mysql -h <endpoint> -u $USUARIO -p dbtest < simple-mysql-dump"
    ;;

limpiar)
    aws rds delete-db-instance --db-instance-identifier "$DB_ID" \
      --skip-final-snapshot --delete-automated-backups --region "$REGION" >/dev/null
    echo "Borrando la instancia (tarda unos minutos)..."
    aws rds wait db-instance-deleted --db-instance-identifier "$DB_ID" --region "$REGION"
    aws ec2 delete-security-group --group-name "$SG_NAME" --region "$REGION" || true
    echo "Limpieza terminada"
    ;;
esac
