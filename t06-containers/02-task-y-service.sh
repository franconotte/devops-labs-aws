#!/usr/bin/env bash
# T06 lab 2, pasos 04 y 05: task definition Fargate + service nginx-app1-svc
set -e
. "$HOME/practica/t06/comun.sh"; cargar

echo "== 04: task definition nginx-app1-td =="
cat > /tmp/nginx-app1-td.json <<JSON
{
  "family": "nginx-app1-td",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "taskRoleArn": "$LABROLE",
  "executionRoleArn": "$LABROLE",
  "containerDefinitions": [
    {
      "name": "nginxapp1",
      "image": "stacksimplify/nginxapp1:latest",
      "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/nginx-app1-td",
          "awslogs-region": "$REGION",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
JSON
TD=$(aws ecs register-task-definition --cli-input-json file:///tmp/nginx-app1-td.json $R --query 'taskDefinition.taskDefinitionArn' --output text)
echo "   $TD"; guardar TD_APP1 "$TD"

echo ""
echo "== 05: service nginx-app1-svc en fargate-demo =="
aws ecs delete-service --cluster fargate-demo --service nginx-app1-svc --force $R >/dev/null 2>&1 || true
aws ecs create-service --cluster fargate-demo --service-name nginx-app1-svc $R \
  --task-definition nginx-app1-td --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB1,$SUB2],securityGroups=[$SG_NGINX],assignPublicIp=ENABLED}" \
  --query 'service.[serviceName,status,desiredCount]' --output text

echo "-- esperando a que la task quede RUNNING"
for i in $(seq 1 30); do
  ARN=$(aws ecs list-tasks --cluster fargate-demo --service-name nginx-app1-svc $R --query 'taskArns[0]' --output text)
  if [ "$ARN" != "None" ] && [ -n "$ARN" ]; then
    EST=$(aws ecs describe-tasks --cluster fargate-demo --tasks "$ARN" $R --query 'tasks[0].lastStatus' --output text)
    echo "   [$i] $EST"
    [ "$EST" = "RUNNING" ] && break
  else
    echo "   [$i] sin task todavia"
  fi
  sleep 15
done

echo "-- IP publica de la task (Fargate con awsvpc: la task tiene su propia ENI)"
ENI=$(aws ecs describe-tasks --cluster fargate-demo --tasks "$ARN" $R \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
IP=$(aws ec2 describe-network-interfaces --network-interface-ids "$ENI" $R --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
echo "   ENI: $ENI   IP: $IP"; guardar IP_APP1 "$IP"

echo "-- probando la app"
for i in $(seq 1 10); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$IP/app1/index.html" || true)
  echo "   [$i] http://$IP/app1/index.html -> $CODE"
  [ "$CODE" = "200" ] && break
  sleep 10
done
curl -s --max-time 10 "http://$IP/app1/index.html" | head -5
