# DevOps Labs — Infraestructura AWS

Laboratorios de infraestructura del **Certificado DevOps (ORT Uruguay)**, resueltos con la
AWS CLI y ejecutados contra una cuenta real. Cada módulo trae sus scripts, un informe de
ejecución con la evidencia obtenida y las decisiones que se apartan de la guía del curso.

| Módulo | Contenido |
|---|---|
| [`t04-cloud`](t04-cloud/) | EC2 en dos AZ, ALB, Auto Scaling, VPC con subnets públicas y privadas + NAT, EFS, S3, RDS |
| [`t05-terraform`](t05-terraform/) | Infrastructure as Code: runner de laboratorios y actualizador de versiones |
| [`t06-containers`](t06-containers/) | ECS: clusters Fargate y EC2, ECR, un ALB con enrutamiento por URI, autoscaling de tasks |
| [`t07-kubernetes`](t07-kubernetes/) | EKS: cluster, node group, deployments y probes |

## Cómo está armado

Los laboratorios del curso se resuelven por consola gráfica. Acá están resueltos **por CLI**,
en scripts idempotentes que se pueden volver a correr y que traen su propia limpieza.
El motivo es simple: lo que se hace a mano en una consola no se puede repetir ni revisar.

Cada módulo incluye un `EJECUCION-REAL.md` con lo que se probó, la evidencia concreta
(IDs de recursos, respuestas HTTP, métricas) y los problemas encontrados.

## Lo que se aprende leyendo los informes

El material del curso tiene varios años y la nube se movió abajo. Los informes documentan,
entre otras cosas: AMIs vencidos, argumentos de Terraform renombrados entre versiones del
provider, combinaciones de motor y clase de instancia que RDS ya no acepta, y las
restricciones específicas del sandbox de AWS Academy.

## Seguridad

No hay credenciales en este repositorio. El `.gitignore` excluye claves privadas,
archivos de state de Terraform —que guardan secretos en texto plano— y los IDs de
recursos efímeros.

## Cronología

Los laboratorios se hicieron entre octubre y noviembre de 2026: T04 Cloud y T05 IaC en
octubre, T06 Containers y T07 Kubernetes en noviembre. Los scripts se escribieron mientras
se ejecutaba cada laboratorio; este repositorio se publicó al final, con un commit por
laboratorio para que el historial sea legible. Las fechas de los commits son las de la
publicación, no las de ejecución.
