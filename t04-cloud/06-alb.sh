#!/usr/bin/env bash
# T04 - 01-IaaS / Lab 2: Application Load Balancer sobre dos EC2
# Levanta 2 instancias con httpd via user-data, un Target Group y un ALB.
#
#   bash 06-alb.sh            -> crea
#   bash 06-alb.sh limpiar    -> borra (usa ids-alb.env)
set -euo pipefail

REGION="us-east-1"
KEY_NAME="lab-t04-key"
IDS_FILE="$(dirname "$0")/ids-alb.env"

if [ "${1:-}" = "limpiar" ]; then
    [ -f "$IDS_FILE" ] || { echo "No existe $IDS_FILE"; exit 1; }
    # shellcheck disable=SC1090
    source "$IDS_FILE"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$REGION" || true
    echo "Esperando a que se borre el ALB..."; sleep 30
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$REGION" || true
    aws ec2 terminate-instances --instance-ids $INSTANCIAS --region "$REGION" >/dev/null || true
    aws ec2 wait instance-terminated --instance-ids $INSTANCIAS --region "$REGION" || true
    aws ec2 delete-security-group --group-id "$SG_WEB" --region "$REGION" || true
    rm -f "$IDS_FILE"
    echo "Limpieza terminada"
    exit 0
fi

VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text)
SUBNET_A=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
  "Name=availability-zone,Values=us-east-1a" --query 'Subnets[0].SubnetId' --output text)
SUBNET_B=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
  "Name=availability-zone,Values=us-east-1b" --query 'Subnets[0].SubnetId' --output text)

echo "== Security Group con HTTP abierto"
SG_WEB=$(aws ec2 create-security-group --group-name lab-t04-web \
  --description "HTTP para el ALB" --vpc-id "$VPC_ID" --region "$REGION" \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_WEB" --protocol tcp --port 80 \
  --cidr 0.0.0.0/0 --region "$REGION" >/dev/null

echo "== user-data: instala httpd y publica el instance-id"
USERDATA=$(mktemp)
cat > "$USERDATA" <<'UD'
#!/bin/bash
yum install -y httpd
systemctl start httpd
systemctl enable httpd
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)
cat > /var/www/html/index.html <<EOF
  <h1>EC2 Web Server</h1>
  <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
  <p><strong>Hostname:</strong> $HOSTNAME</p>
EOF
UD

AMI=$(aws ec2 describe-images --owners amazon --region "$REGION" \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)

echo "== Lanzando dos instancias web (una por AZ)"
INSTANCIAS=""
for par in "web01:$SUBNET_A" "web02:$SUBNET_B"; do
    NOMBRE="${par%%:*}"; SUBNET="${par##*:}"
    ID=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" --count 1 \
      --instance-type t3.micro --key-name "$KEY_NAME" --security-group-ids "$SG_WEB" \
      --subnet-id "$SUBNET" --associate-public-ip-address \
      --user-data "file://$USERDATA" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NOMBRE}]" \
      --query 'Instances[0].InstanceId' --output text)
    INSTANCIAS="$INSTANCIAS $ID"
    echo "  $NOMBRE -> $ID"
done
rm -f "$USERDATA"
aws ec2 wait instance-running --instance-ids $INSTANCIAS --region "$REGION"

echo "== Target Group (health check en /index.html)"
TG_ARN=$(aws elbv2 create-target-group --name lab-t04-tg --protocol HTTP --port 80 \
  --vpc-id "$VPC_ID" --health-check-path /index.html --target-type instance \
  --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text)
for ID in $INSTANCIAS; do
    aws elbv2 register-targets --target-group-arn "$TG_ARN" --targets "Id=$ID" --region "$REGION"
done

echo "== Application Load Balancer"
ALB_ARN=$(aws elbv2 create-load-balancer --name lab-t04-alb \
  --subnets "$SUBNET_A" "$SUBNET_B" --security-groups "$SG_WEB" --type application \
  --region "$REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TG_ARN" --region "$REGION" >/dev/null

echo "== Esperando a que el ALB quede activo (1-3 minutos)"
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN" --region "$REGION"
DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" \
  --query 'LoadBalancers[0].DNSName' --output text)

printf 'ALB_ARN=%s\nTG_ARN=%s\nSG_WEB=%s\nINSTANCIAS="%s"\n' "$ALB_ARN" "$TG_ARN" "$SG_WEB" "$INSTANCIAS" > "$IDS_FILE"

echo ""
echo "URL del balanceador: http://$DNS"
echo "Refrescá varias veces: el Instance ID tiene que alternar entre las dos instancias."
echo ""
echo "Prueba del lab (para discutir): apagá una instancia y mirá el Target Group"
echo "  aws ec2 stop-instances --instance-ids <id> --region $REGION"
echo "  aws elbv2 describe-target-health --target-group-arn $TG_ARN --region $REGION --output table"
echo ""
echo "Al terminar: bash 06-alb.sh limpiar"
