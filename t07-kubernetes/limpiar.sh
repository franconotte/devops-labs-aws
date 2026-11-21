#!/usr/bin/env bash
# T07: borrar EKS. El control plane cuesta USD 0.10/hora aunque este vacio.
. "$HOME/practica/t07/comun.sh"
echo "== borrando objetos de Kubernetes (para que se vayan los ELB que creo) =="
kubectl delete deployment 2048-app --ignore-not-found 2>/dev/null
kubectl delete svc svc-2048 --ignore-not-found 2>/dev/null
kubectl delete pod pod-2048 --ignore-not-found 2>/dev/null
sleep 20
echo "== node group =="
aws eks delete-nodegroup --cluster-name eks-cluster --nodegroup-name workers $R --query 'nodegroup.status' --output text 2>/dev/null
for i in $(seq 1 40); do
  aws eks describe-nodegroup --cluster-name eks-cluster --nodegroup-name workers $R >/dev/null 2>&1 || break
  echo "   [$i] borrando nodos..."; sleep 30
done
echo "== cluster =="
aws eks delete-cluster --name eks-cluster $R --query 'cluster.status' --output text 2>/dev/null
for i in $(seq 1 40); do
  aws eks describe-cluster --name eks-cluster $R >/dev/null 2>&1 || break
  echo "   [$i] borrando cluster..."; sleep 30
done
echo ""
echo "=== verificacion ==="
echo "EKS:"; aws eks list-clusters $R --query clusters --output text
echo "ELB clasicos:"; aws elb describe-load-balancers $R --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text 2>/dev/null
echo "ALB:"; aws elbv2 describe-load-balancers $R --query 'LoadBalancers[].LoadBalancerName' --output text
echo "Instancias:"; aws ec2 describe-instances $R --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' --output text
