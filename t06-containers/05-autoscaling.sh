#!/usr/bin/env bash
# T06 lab 4, parte 2: autoscaling por Target Tracking sobre RequestCountPerTarget
set -e
. "$HOME/practica/t06/comun.sh"; cargar

echo "== el lab pide min 1 / deseado 1 / max 3 =="
aws ecs update-service --cluster fargate-demo --service aws-nginx-app1-svc --desired-count 1 $R \
  --query 'service.desiredCount' --output text

echo "== registrando el scalable target =="
aws application-autoscaling register-scalable-target $R \
  --service-namespace ecs --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/fargate-demo/aws-nginx-app1-svc \
  --min-capacity 1 --max-capacity 3

# el sufijo que pide la metrica es "app/<lb>/<id>/targetgroup/<tg>/<id>"
LB_SUFIJO=$(echo "$ALB" | sed 's|.*:loadbalancer/||')
TG_SUFIJO=$(echo "$TG1" | sed 's|.*:||')
echo "== politica RequestPerTarget, valor objetivo 1000 =="
cat > /tmp/pol.json <<JSON
{
  "TargetValue": 1000.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ALBRequestCountPerTarget",
    "ResourceLabel": "${LB_SUFIJO}/${TG_SUFIJO}"
  },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 60
}
JSON
aws application-autoscaling put-scaling-policy $R \
  --service-namespace ecs --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/fargate-demo/aws-nginx-app1-svc \
  --policy-name RequestPerTarget --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file:///tmp/pol.json \
  --query 'Alarms[].AlarmName' --output text

echo ""
echo "== politica aplicada =="
aws application-autoscaling describe-scaling-policies $R --service-namespace ecs \
  --resource-id service/fargate-demo/aws-nginx-app1-svc \
  --query 'ScalingPolicies[].{Politica:PolicyName,Tipo:PolicyType,Objetivo:TargetTrackingScalingPolicyConfiguration.TargetValue,Metrica:TargetTrackingScalingPolicyConfiguration.PredefinedMetricSpecification.PredefinedMetricType}' --output table
aws application-autoscaling describe-scalable-targets $R --service-namespace ecs \
  --resource-ids service/fargate-demo/aws-nginx-app1-svc \
  --query 'ScalableTargets[].{Min:MinCapacity,Max:MaxCapacity}' --output table
