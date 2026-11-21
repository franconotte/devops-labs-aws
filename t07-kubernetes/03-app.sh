#!/usr/bin/env bash
# T07 parte 3: desplegar el 2048, imperativo y declarativo
set -e
. "$HOME/practica/t07/comun.sh"
cd "$HOME/practica/t07"

echo "############ MODO IMPERATIVO ############"
kubectl delete pod pod-2048 --ignore-not-found >/dev/null 2>&1
kubectl delete svc svc-2048 --ignore-not-found >/dev/null 2>&1
echo "== kubectl run =="
kubectl run pod-2048 --image=evilroot/docker-2048 -l app=pod-2048
kubectl wait --for=condition=Ready pod/pod-2048 --timeout=180s
echo "== exponiendo con type=LoadBalancer (crea un ELB real en AWS) =="
kubectl expose pod pod-2048 --port=80 --name=svc-2048 --type=LoadBalancer
echo "== esperando el hostname del balanceador =="
for i in $(seq 1 30); do
  LB=$(kubectl get svc svc-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$LB" ] && break
  echo "   [$i] aun sin hostname"; sleep 10
done
echo "   $LB"
echo "== kubectl get all =="
kubectl get all
echo "== el ELB que creo Kubernetes, visto desde AWS =="
aws elb describe-load-balancers $R --query 'LoadBalancerDescriptions[].{Nombre:LoadBalancerName,DNS:DNSName}' --output table 2>/dev/null | head -8
echo "== probando la app (el ELB tarda ~2 min en responder) =="
for i in $(seq 1 24); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$LB/" || true)
  echo "   [$i] http://$LB/ -> $CODE"
  [ "$CODE" = "200" ] && break
  sleep 15
done
curl -s --max-time 10 "http://$LB/" | grep -oE "<title>[^<]*</title>" | head -1

echo ""
echo "== borrando service y pod, como pide el lab =="
kubectl delete svc svc-2048
kubectl delete pod pod-2048

echo ""
echo "############ MODO DECLARATIVO ############"
kubectl create -f manifiestos/pod-2048.yaml
kubectl wait --for=condition=Ready pod/pod-2048 --timeout=180s
kubectl get pod pod-2048 -o wide
echo "== exponiendo el pod declarativo (ClusterIP) =="
kubectl expose pod pod-2048 --port=80 --name=svc-2048
kubectl get svc svc-2048
echo "== probando desde adentro del cluster =="
kubectl run probe --rm -i --restart=Never --image=curlimages/curl --command -- curl -s -o /dev/null -w "respuesta del service: %{http_code}\n" --max-time 10 http://svc-2048/
kubectl delete svc svc-2048 >/dev/null
kubectl delete pod pod-2048 >/dev/null
echo "limpio para la parte 4"
