#!/usr/bin/env bash
# T06 lab 4: un solo ALB para dos apps, con enrutamiento por URI
set -e
. "$HOME/practica/t06/comun.sh"; cargar

echo "== 03: Application Load Balancer =="
SG_ALB=$(aws ec2 describe-security-groups $R --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=alb-ecs-nginx" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_ALB" = "None" ]; then
  SG_ALB=$(aws ec2 create-security-group --group-name alb-ecs-nginx --description "ALB publico puerto 80" --vpc-id "$VPC_ID" $R --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG_ALB" --protocol tcp --port 80 --cidr 0.0.0.0/0 $R >/dev/null
fi
guardar SG_ALB "$SG_ALB"

ALB=$(aws elbv2 describe-load-balancers --names aws-ecs-nginx-lb $R --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -z "$ALB" ] || [ "$ALB" = "None" ]; then
  ALB=$(aws elbv2 create-load-balancer --name aws-ecs-nginx-lb --subnets "$SUB1" "$SUB2" --security-groups "$SG_ALB" $R --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi
DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB" $R --query 'LoadBalancers[0].DNSName' --output text)
echo "   $DNS"; guardar ALB "$ALB"; guardar DNS "$DNS"

echo "== target groups: app1 por IP (Fargate/awsvpc), app2 por instancia (EC2/bridge) =="
crear_tg() {
  local nombre=$1 tipo=$2 hc=$3 arn
  arn=$(aws elbv2 describe-target-groups --names "$nombre" $R --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
  if [ -z "$arn" ] || [ "$arn" = "None" ]; then
    arn=$(aws elbv2 create-target-group --name "$nombre" --protocol HTTP --port 80 --vpc-id "$VPC_ID" \
      --target-type "$tipo" --health-check-path "$hc" $R --query 'TargetGroups[0].TargetGroupArn' --output text)
  fi
  echo "$arn"
}
TG1=$(crear_tg ecs-nginx-app1-tg ip /app1/index.html)
TG2=$(crear_tg ecs-nginx-app2-tg instance /app2/index.html)
echo "   app1: $TG1"; echo "   app2: $TG2"; guardar TG1 "$TG1"; guardar TG2 "$TG2"

echo "== listener con reglas /app1* y /app2* =="
LIS=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB" $R --query 'Listeners[0].ListenerArn' --output text 2>/dev/null || true)
if [ -z "$LIS" ] || [ "$LIS" = "None" ]; then
  LIS=$(aws elbv2 create-listener --load-balancer-arn "$ALB" --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG1" $R --query 'Listeners[0].ListenerArn' --output text)
fi
aws elbv2 describe-rules --listener-arn "$LIS" $R --query 'Rules[?Priority!=`default`].RuleArn' --output text | tr '\t' '\n' | while read -r r; do
  [ -n "$r" ] && aws elbv2 delete-rule --rule-arn "$r" $R >/dev/null 2>&1 || true
done
aws elbv2 create-rule --listener-arn "$LIS" --priority 10 $R \
  --conditions '[{"Field":"path-pattern","Values":["/app1*"]}]' \
  --actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"$TG1\"}]" >/dev/null
aws elbv2 create-rule --listener-arn "$LIS" --priority 20 $R \
  --conditions '[{"Field":"path-pattern","Values":["/app2*"]}]' \
  --actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"$TG2\"}]" >/dev/null
echo "   listener $LIS con 2 reglas"; guardar LIS "$LIS"

echo ""
echo "== 04: task definitions para las dos apps =="
cat > /tmp/td-app1.json <<JSON
{ "family":"aws-nginx-app1","networkMode":"awsvpc","requiresCompatibilities":["FARGATE"],
  "cpu":"256","memory":"512","taskRoleArn":"$LABROLE","executionRoleArn":"$LABROLE",
  "containerDefinitions":[{"name":"nginxapp1","image":"${ECR_REGISTRY}/nginxapp1:latest",
    "portMappings":[{"containerPort":80,"protocol":"tcp"}],"essential":true,
    "logConfiguration":{"logDriver":"awslogs","options":{"awslogs-group":"/ecs/aws-nginx-app1",
      "awslogs-region":"$REGION","awslogs-stream-prefix":"ecs","awslogs-create-group":"true"}}}]}
JSON
cat > /tmp/td-app2.json <<JSON
{ "family":"aws-nginx-app2","networkMode":"bridge","requiresCompatibilities":["EC2"],
  "taskRoleArn":"$LABROLE","executionRoleArn":"$LABROLE",
  "containerDefinitions":[{"name":"nginxapp2","image":"${ECR_REGISTRY}/nginxapp2:latest",
    "cpu":256,"memory":512,
    "portMappings":[{"containerPort":80,"hostPort":0,"protocol":"tcp"}],"essential":true,
    "logConfiguration":{"logDriver":"awslogs","options":{"awslogs-group":"/ecs/aws-nginx-app2",
      "awslogs-region":"$REGION","awslogs-stream-prefix":"ecs","awslogs-create-group":"true"}}}]}
JSON
aws ecs register-task-definition --cli-input-json file:///tmp/td-app1.json $R --query 'taskDefinition.taskDefinitionArn' --output text
aws ecs register-task-definition --cli-input-json file:///tmp/td-app2.json $R --query 'taskDefinition.taskDefinitionArn' --output text

echo ""
echo "== 05: service de app1 en Fargate, detras del ALB =="
aws ecs delete-service --cluster fargate-demo --service aws-nginx-app1-svc --force $R >/dev/null 2>&1 || true
aws ecs create-service --cluster fargate-demo --service-name aws-nginx-app1-svc $R \
  --task-definition aws-nginx-app1 --desired-count 2 --launch-type FARGATE \
  --health-check-grace-period-seconds 147 \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB1,$SUB2],securityGroups=[$SG_NGINX],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG1,containerName=nginxapp1,containerPort=80" \
  --query 'service.[serviceName,status]' --output text

echo "== 06: service de app2 en EC2, mismo ALB =="
aws ecs delete-service --cluster ecs-ec2-demo --service aws-nginx-app2-svc --force $R >/dev/null 2>&1 || true
aws ecs create-service --cluster ecs-ec2-demo --service-name aws-nginx-app2-svc $R \
  --task-definition aws-nginx-app2 --desired-count 2 --launch-type EC2 \
  --health-check-grace-period-seconds 147 \
  --load-balancers "targetGroupArn=$TG2,containerName=nginxapp2,containerPort=80" \
  --query 'service.[serviceName,status]' --output text
