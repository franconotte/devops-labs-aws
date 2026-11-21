# T04 ejecutado contra AWS real — 2026-10-22

Cuenta del Learner Lab `846774845101`, region `us-east-1`.

## Labs verificados

| Lab | Prueba concreta |
|---|---|
| 01-IaaS/5 — CLI | `instancia-desde-cli` running, encontrada por su tag Name |
| 01-IaaS/1 — EC2 en 2 AZ | `test-instance01` en us-east-1a, `test-instance02` en us-east-1b |
| 01-IaaS/2 — ALB | 2 targets healthy; el ALB alterno entre las dos instancias |
| 01-IaaS/4 — user-data + AMI | la web respondio HTTP 200; AMI `html-web-ami` quedo `available` |
| 01-IaaS/3 — ASG | termine una instancia a mano y el ASG la reemplazo en ~90 s |
| 02-networking/2 — VPC por CLI | VPC 10.0.0.0/16 + IGW + route table + EC2 adentro |
| 02-networking/3 — publica/privada | la instancia privada salio a internet con la IP del NAT (100.56.152.203), HTTP 200 |
| 03-storage — EFS | montado en las dos AZ; archivo escrito en 1a y leido desde 1b |
| 03-storage/4 — S3 sitio | http://fnotte-bucket.s3-website-us-east-1.amazonaws.com responde 200 |
| 04 — RDS MySQL | conectado desde una EC2, `create database dbtest`, MySQL 8.4.11 |
| 01-IaaS/7 — integrador A | ASG enganchado al Target Group: 4 targets healthy a la vez |

## Bugs encontrados al correrlo de verdad

1. **`sg-puerto-80`** — AWS no permite nombres de Security Group que empiecen con `sg-`. Renombrado a `puerto-80`.
2. **`05-rds.sh` no era idempotente** — fallaba si el SG `lab-t04-rds` ya existia. Ahora reusa el que haya.
3. **`05-rds.sh`, ultima linea** — `"$0" estado` fallaba con "command not found". Ahora es `bash "$0" estado`.
4. **El `read -s` del password** muere con `set -e` si la entrada no termina en salto de linea.
5. **`efs-utils` no resuelve el DNS** en estas instancias. Se monta por IP del mount target con `-t nfs4`.
6. **ProxyJump (`ssh -J`) al bastion no funciona**; con agent forwarding (`ssh -A`) si.
7. **Limite de instancias del Learner Lab**: con 9 corriendo, termino sola la decima.

## Lo que queda pendiente, y por que

- **Lab 6 (Windows por RDP)**: va si o si por consola grafica. Guia en `09-consola-windows-e-integrador.md`.
- **Integrador parte B** (mover el ASG a subnets privadas): el ASG vive en la VPC default y las subnets privadas estaban en otra VPC. El comando es
  `aws autoscaling update-auto-scaling-group --auto-scaling-group-name asg-devops --vpc-zone-identifier <subnets privadas>`
  y requiere crear el ASG dentro de la misma VPC que las privadas.

## Estado al cerrar

Borrado todo lo que cobra por hora: RDS, ALB, ASG, NAT Gateway, Elastic IP, EFS y las dos VPC propias.
Quedan `test-instance01` y `test-instance02` (el Learner Lab las apaga solo) y los buckets S3, que practicamente no cuestan.
