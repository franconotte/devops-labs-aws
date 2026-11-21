#!/usr/bin/env bash
# T06 lab 3: desplegar en ECS la imagen propia alojada en ECR
set -e
. "$HOME/practica/t06/comun.sh"; cargar

echo "== imagen en ECR =="
aws ecr describe-images --repository-name aws-ecr-nginx $R \
  --query 'imageDetails[].{Tag:imageTags[0],MB:imageSizeInBytes,Subida:imagePushedAt}' --output table

echo "== task definition que usa la imagen de ECR =="
cat > /tmp/ecr-td.json <<JSON
{
  "family": "aws-ecr-nginx-td",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "taskRoleArn": "$LABROLE",
  "executionRoleArn": "$LABROLE",
  "containerDefinitions": [{
    "name": "ecrnginx",
    "image": "${ECR_REGISTRY}/aws-ecr-nginx:1.0.0",
    "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
    "essential": true,
    "logConfiguration": {"logDriver":"awslogs","options":{
      "awslogs-group":"/ecs/aws-ecr-nginx-td","awslogs-region":"$REGION",
      "awslogs-stream-prefix":"ecs","awslogs-create-group":"true"}}
  }]
}
JSON
aws ecs register-task-definition --cli-input-json file:///tmp/ecr-td.json $R --query 'taskDefinition.taskDefinitionArn' --output text

echo "== corriendo la task =="
ARN=$(aws ecs run-task --cluster fargate-demo --task-definition aws-ecr-nginx-td --launch-type FARGATE $R \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB1],securityGroups=[$SG_NGINX],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)
echo "   $ARN"
for i in $(seq 1 25); do
  EST=$(aws ecs describe-tasks --cluster fargate-demo --tasks "$ARN" $R --query 'tasks[0].lastStatus' --output text)
  echo "   [$i] $EST"; [ "$EST" = "RUNNING" ] && break; sleep 12
done
ENI=$(aws ecs describe-tasks --cluster fargate-demo --tasks "$ARN" $R --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
IP=$(aws ec2 describe-network-interfaces --network-interface-ids "$ENI" $R --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
echo "   IP: $IP"
for i in $(seq 1 10); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$IP/" || true)
  echo "   [$i] http://$IP/ -> $CODE"; [ "$CODE" = "200" ] && break; sleep 8
done
echo "--- contenido servido ---"
curl -s --max-time 10 "http://$IP/" | head -8
echo "--- apagando la task del lab 3 ---"
aws ecs stop-task --cluster fargate-demo --task "$ARN" $R --query 'task.lastStatus' --output text
