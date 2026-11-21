#!/usr/bin/env bash
# T06: baja todo lo que cobra. Deja la VPC y los repos de ECR (no cuestan).
. "$HOME/practica/t06/comun.sh"; cargar
echo "== autoscaling =="
aws application-autoscaling deregister-scalable-target $R --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount --resource-id service/fargate-demo/aws-nginx-app1-svc 2>/dev/null && echo "   target dado de baja"
echo "== servicios =="
for par in "fargate-demo:aws-nginx-app1-svc" "fargate-demo:nginx-app1-svc" "ecs-ec2-demo:aws-nginx-app2-svc"; do
  C="${par%%:*}"; S="${par##*:}"
  aws ecs delete-service --cluster "$C" --service "$S" --force $R >/dev/null 2>&1 && echo "   $S borrado"
done
sleep 20
echo "== ALB, listener y target groups =="
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB" $R 2>/dev/null && echo "   ALB borrado"
sleep 30
aws elbv2 delete-target-group --target-group-arn "$TG1" $R 2>/dev/null && echo "   TG app1 borrado"
aws elbv2 delete-target-group --target-group-arn "$TG2" $R 2>/dev/null && echo "   TG app2 borrado"
echo "== ASG y launch template (apaga la EC2 del cluster) =="
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name ecs-ec2-asg --force-delete $R 2>/dev/null && echo "   ASG borrado"
for i in $(seq 1 30); do
  N=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ecs-ec2-asg $R --query 'length(AutoScalingGroups)' --output text 2>/dev/null)
  [ "$N" = "0" ] && break; sleep 10
done
aws ec2 delete-launch-template --launch-template-id "$LT" $R >/dev/null 2>&1 && echo "   launch template borrado"
echo "== clusters =="
aws ecs delete-cluster --cluster fargate-demo $R --query 'cluster.status' --output text 2>/dev/null
aws ecs delete-cluster --cluster ecs-ec2-demo $R --query 'cluster.status' --output text 2>/dev/null
echo ""
echo "=== verificacion ==="
echo "Load balancers:"; aws elbv2 describe-load-balancers $R --query 'LoadBalancers[].LoadBalancerName' --output text
echo "Instancias corriendo:"; aws ec2 describe-instances $R --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' --output text
echo "Clusters ECS:"; aws ecs list-clusters $R --query 'clusterArns' --output text
echo "Repos ECR (se dejan, no cuestan):"; aws ecr describe-repositories $R --query 'repositories[].repositoryName' --output text
