# T07 Kubernetes (EKS) ejecutado contra AWS real — 2026-11-21

Cuenta del Learner Lab `846774845101`, region `us-east-1`.
Scripts y manifiestos en `~/practica/t07/`. Preguntas de los labs resueltas en `preguntas.md`.

## Las 5 partes

| Parte | Prueba concreta |
|---|---|
| 1 Desplegando un cluster | `kubectl v1.37.2` instalado en `~/.local/bin` (sin sudo). Cluster **eks-cluster**, EKS **1.37**, ACTIVE, con `LabRole` |
| 2 Desplegando workers | Node group `workers`: 2 nodos `t3.medium` ACTIVE, uno por AZ, Amazon Linux 2023 con containerd. `kubectl get nodes` los muestra **Ready** |
| 3 Desplegando una app | **Imperativo:** `kubectl run` + `expose --type=LoadBalancer` creo un ELB real en AWS; el 2048 respondio HTTP 200 con `<title>2048</title>`. **Declarativo:** mismo pod por YAML, expuesto como ClusterIP y probado desde adentro del cluster |
| 4 Trabajando con deployments | Pod suelto borrado: **no vuelve**. Pod de un Deployment borrado: **el ReplicaSet lo repone** en segundos con nombre nuevo, replicas de vuelta en 2/2 |
| 5 Trabajando con probes | Deployment actualizado con readiness (delay 30s) y liveness (delay 15s). `kubectl describe` los muestra exactamente como el lab indica |

## Evidencia del punto central de la parte 4

```
deployment.apps/2048-app      2/2     2            2
replicaset.apps/2048-app-...  2       2            2
pod/2048-app-8497c76659-ctfcx   Running   24s     <- sobreviviente
pod/2048-app-8497c76659-rkdgt   Running   15s     <- repuesto tras el delete
```

La diferencia de edad entre los dos pods es la prueba: uno tiene 24 segundos y el otro 15,
porque el segundo nacio cuando borre al original. Es el mismo *reconciliation loop* del
Auto Scaling Group del T04 y del service de ECS del T06.

## Decisiones distintas de la guia

| Que | Por que |
|---|---|
| Todo por CLI en vez de consola | la guia es por consola; el resultado es identico y queda reproducible |
| `kubectl` instalado en `~/.local/bin` | la guia usa `sudo install` en `/usr/local/bin`; sin sudo funciona igual |
| `LabRole` como rol del cluster **y** de los nodos | en una cuenta real son dos roles distintos; AWS Academy los unifica porque prohibe crear roles IAM |
| Se reuso la VPC del T06 | evita crear otra; se le agrego el tag `kubernetes.io/role/elb=1` a las subnets publicas, **necesario** para que los Service type=LoadBalancer sepan donde poner el ELB |
| `t3.medium` en los workers | `t3.micro` no alcanza: el kubelet y los pods de sistema no entran |

## Costo

El control plane de EKS cuesta **USD 0.10/hora** aunque no haya pods, mas las dos `t3.medium`.
Es lo mas caro de todo el certificado. Borrado al terminar: node group, cluster y los ELB
que Kubernetes habia creado solo.
