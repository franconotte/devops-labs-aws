#!/usr/bin/env bash
# T07 partes 4 y 5: deployments, autorreparacion y probes
set -e
. "$HOME/practica/t07/comun.sh"
cd "$HOME/practica/t07"

echo "############ PARTE 4.1: un POD suelto no tiene quien lo cuide ############"
kubectl run pod-2048 --image=evilroot/docker-2048 -l app=app-2048
kubectl wait --for=condition=Ready pod/pod-2048 --timeout=180s
echo "-- pods antes de borrar:"; kubectl get pods
echo "-- borro el pod:"; kubectl delete pod pod-2048
echo "-- pods despues (5s):"; sleep 5; kubectl get pods 2>&1 | head -3
echo ">>> no volvio: nadie lo reponia <<<"

echo ""
echo "############ PARTE 4.2: el mismo caso con un Deployment ############"
kubectl delete deployment 2048-app --ignore-not-found >/dev/null 2>&1
kubectl create -f manifiestos/deployment.yaml
kubectl rollout status deployment/2048-app --timeout=180s
echo "-- los 2 pods del deployment:"; kubectl get pods -l app=2048-app
VICTIMA=$(kubectl get pods -l app=2048-app -o jsonpath='{.items[0].metadata.name}')
echo "-- borro a mano: $VICTIMA"
kubectl delete pod "$VICTIMA"
sleep 8
echo "-- pods despues:"; kubectl get pods -l app=2048-app
echo ">>> el ReplicaSet repuso el pod: nombre nuevo, replicas de vuelta en 2 <<<"
echo "-- la cadena de objetos:"; kubectl get deploy,rs,pods -l app=2048-app

echo ""
echo "############ PARTE 5: readiness y liveness probes ############"
kubectl apply -f manifiestos/deployment-probes.yaml
kubectl rollout status deployment/2048-app --timeout=240s
POD=$(kubectl get pods -l app=2048-app -o jsonpath='{.items[0].metadata.name}')
echo "-- probes configurados en $POD:"
kubectl describe pod "$POD" | grep -E "Liveness|Readiness"
echo "-- estado de los pods (Ready 1/1 = paso la readiness):"
kubectl get pods -l app=2048-app
echo "-- eventos del pod:"
kubectl describe pod "$POD" | sed -n '/Events:/,$p' | head -10
