#!/usr/bin/env bash
# T04 - 01-IaaS / Labs 3 y 4: AMI custom, Launch Template y Auto Scaling Group
#
#   bash 07-asg-y-ami.sh ami       -> Lab 4: instancia con user-data + AMI custom
#   bash 07-asg-y-ami.sh asg       -> Lab 3: Launch Template + ASG (usa la AMI si existe)
#   bash 07-asg-y-ami.sh limpiar
set -euo pipefail

REGION="us-east-1"
KEY_NAME="lab-t04-key"
LT_NAME="test-lt-devops"
ASG_NAME="asg-devops"
AMI_NAME="html-web-ami"

case "${1:-ami}" in

ami)
    echo "== Lab 4, Parte A: instancia configurada con user-data"
    VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
    SG_ID=$(aws ec2 create-security-group --group-name lab-t04-http --description "HTTP" \
      --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text 2>/dev/null \
      || aws ec2 describe-security-groups --group-names lab-t04-http --region "$REGION" --query 'SecurityGroups[0].GroupId' --output text)
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 \
      --cidr 0.0.0.0/0 --region "$REGION" >/dev/null 2>&1 || true

    UD=$(mktemp)
    cat > "$UD" <<'UDATA'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl enable httpd
curl -O https://gist.githubusercontent.com/mauricioamendola/9113b526ecb157724187fabddaa95aa8/raw/f424d19c98745843f2abcddd2a7de296ada93880/index.html
mv index.html /var/www/html
systemctl start httpd
UDATA

    AMI_BASE=$(aws ec2 describe-images --owners amazon --region "$REGION" \
      --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
      --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)

    ID=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI_BASE" --count 1 \
      --instance-type t3.micro --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
      --user-data "file://$UD" \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=html-web-instance01}]' \
      --query 'Instances[0].InstanceId' --output text)
    rm -f "$UD"
    echo "Instancia: $ID — esperando a que este running"
    aws ec2 wait instance-running --instance-ids "$ID" --region "$REGION"
    IP=$(aws ec2 describe-instances --instance-ids "$ID" --region "$REGION" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "Probar en el browser: http://$IP   (esperá ~2 min a que termine el user-data)"

    echo ""
    echo "== Lab 4, Parte B: crear la AMI custom"
    echo "   (hacelo cuando la web ya responda)"
    echo "   aws ec2 create-image --instance-id $ID --name $AMI_NAME --region $REGION"
    ;;

asg)
    echo "== Lab 3: Launch Template + Auto Scaling Group"
    AMI_ID=$(aws ec2 describe-images --owners self --region "$REGION" \
      --filters "Name=name,Values=$AMI_NAME" --query 'Images[0].ImageId' --output text 2>/dev/null || echo "None")
    if [ "$AMI_ID" = "None" ] || [ -z "$AMI_ID" ]; then
        echo "   (no encontre la AMI custom, uso Amazon Linux)"
        AMI_ID=$(aws ec2 describe-images --owners amazon --region "$REGION" \
          --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
          --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)
    fi
    echo "   AMI: $AMI_ID"

    SG_ID=$(aws ec2 describe-security-groups --group-names lab-t04-ssh --region "$REGION" \
      --query 'SecurityGroups[0].GroupId' --output text)

    aws ec2 create-launch-template --launch-template-name "$LT_NAME" --region "$REGION" \
      --launch-template-data "{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"t3.micro\",\"KeyName\":\"$KEY_NAME\",\"SecurityGroupIds\":[\"$SG_ID\"]}" \
      --query 'LaunchTemplate.LaunchTemplateId' --output text

    VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
    SUBNETS=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" \
      "Name=availability-zone,Values=us-east-1a,us-east-1b" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')

    aws autoscaling create-auto-scaling-group --region "$REGION" \
      --auto-scaling-group-name "$ASG_NAME" \
      --launch-template "LaunchTemplateName=$LT_NAME,Version=\$Latest" \
      --min-size 1 --max-size 2 --desired-capacity 1 \
      --vpc-zone-identifier "$SUBNETS"

    echo "ASG creado. Instancias que levanto:"
    sleep 20
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
      --region "$REGION" --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,AvailabilityZone]' --output table

    echo ""
    echo "Preguntas del lab, para probar:"
    echo "  1) Terminá a mano una instancia del ASG y mirá como la reemplaza (auto-healing):"
    echo "     aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $REGION"
    echo "  2) Subí el deseado a 2:"
    echo "     aws autoscaling set-desired-capacity --auto-scaling-group-name $ASG_NAME --desired-capacity 2 --region $REGION"
    echo "  3) Nueva version del Launch Template:"
    echo "     aws ec2 create-launch-template-version --launch-template-name $LT_NAME --source-version 1 --launch-template-data '{\"InstanceType\":\"t3.small\"}' --region $REGION"
    ;;

limpiar)
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete --region "$REGION" || true
    aws ec2 delete-launch-template --launch-template-name "$LT_NAME" --region "$REGION" || true
    IDS=$(aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag:Name,Values=html-web-instance01" "Name=instance-state-name,Values=running,pending,stopped" \
      --query 'Reservations[].Instances[].InstanceId' --output text)
    [ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS --region "$REGION" >/dev/null
    AMI_ID=$(aws ec2 describe-images --owners self --region "$REGION" --filters "Name=name,Values=$AMI_NAME" --query 'Images[0].ImageId' --output text 2>/dev/null || echo "None")
    [ "$AMI_ID" != "None" ] && [ -n "$AMI_ID" ] && aws ec2 deregister-image --image-id "$AMI_ID" --region "$REGION" || true
    aws ec2 delete-security-group --group-name lab-t04-http --region "$REGION" 2>/dev/null || true
    echo "Limpieza terminada"
    ;;
esac
