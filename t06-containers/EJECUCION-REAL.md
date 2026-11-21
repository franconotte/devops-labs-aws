# T06 Containers (ECS) ejecutado contra AWS real — 2026-11-21

Cuenta del Learner Lab `846774845101`, region `us-east-1`.
Scripts en `~/practica/t06/`, material del curso en `~/practica/t06/Laboratorios`.

## Los 4 labs

| Lab | Prueba concreta |
|---|---|
| 01 Conceptos | Teorico. Resumen de container definition / task definition / task / service / cluster y Fargate vs EC2 |
| 02 Crear cluster ECS | VPC 10.0.0.0/16 con 2 subnets publicas; clusters `fargate-demo` y `ecs-ec2-demo` ACTIVE con Container Insights; task definition `nginx-app1-td`; service `nginx-app1-svc` sirviendo HTTP 200 en su IP publica |
| 03 ECR | Repo `aws-ecr-nginx`; imagen construida local, pusheada y desplegada en ECS desde ECR, sirviendo su propio index.html |
| 04 Load Balancing | Un solo ALB con enrutamiento por URI: `/app1*` -> Fargate, `/app2*` -> EC2. 4 targets healthy simultaneos |
| 04 Autoscaling | Target Tracking sobre ALBRequestCountPerTarget, objetivo 1000, min 1 / max 3. **Escalo de 1 a 3 tasks** con un pico medido de **7444 req/min por target** |

## Lo que mejor muestra la diferencia entre los dos launch types

Los target groups lo dejan ver sin explicacion:

- **app1 (Fargate, red `awsvpc`)**: targets `10.0.1.37` y `10.0.2.146` — dos IPs distintas, cada task con su propia ENI.
- **app2 (EC2, red `bridge`)**: targets `i-07c5ecc48e9a1820f:32768` y `i-07c5ecc48e9a1820f:32769` — **la misma instancia dos veces**, con puertos efimeros. Eso es dynamic port mapping.

## Decisiones distintas de la guia

| Que | Por que |
|---|---|
| `t3.small` en vez de `t2.small` | el Learner Lab deniega varios tipos t2 |
| Cluster EC2 armado con launch template + ASG | la consola lo hace sola; por CLI hay que crear la capacidad a mano, con `ECS_CLUSTER` en user-data |
| `LabRole` como task role y execution role | el sandbox prohibe crear roles IAM; AWS Academy ya provee este |
| `LabInstanceProfile` en las instancias | mismo motivo |
| Build y push desde **Windows**, no desde WSL | Docker Desktop no expone el socket a WSL en esta maquina |
| Carga con curl en paralelo en vez de ApacheBench | `ab` no estaba instalado; 50 workers alcanzaron 7444 req/min, de sobra para disparar la alarma |

## Detalle que costo tiempo

`docker login` a ECR fallaba con **400 Bad Request** al pasar el token por el pipe de PowerShell
(`wsl ... | docker login --password-stdin`): el pipe corrompe el token. Funciona leyendo el
token a una variable con `[IO.File]::ReadAllText()` y pasandolo por `--password`.

## Limpieza

Borrado: servicios, ALB, target groups, ASG, launch template, los dos clusters y **todas las instancias EC2**
(incluidas las dos sobrantes del T04). Se dejan la VPC y los 3 repos de ECR, que no generan costo.
