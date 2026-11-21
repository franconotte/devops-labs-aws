# T05 ejecutado contra AWS real — 2026-10-25

Cuenta del Learner Lab `846774845101`, region `us-east-1`, Terraform v1.16.6, provider aws 6.70.0.
Material clonado en `~/practica/t05/Laboratorios`, copias ejecutables en `~/practica/t05/labs`.

## Secciones 01 a 05: 29 de 29 configuraciones, con apply y destroy verificados

| Seccion | Configuraciones | Que se probo |
|---|---|---|
| 01 Basics | 3 | ciclo init/validate/fmt/plan/apply/show/destroy; EC2 creada y leida del state |
| 02 Fundamental Blocks | 4 | required_version compatible y roto; provider con alias multi-region; lock file regenerado de aws 2.50.0 a 6.70.0 |
| 03 Resources | 8 | sintaxis, depends_on (9 recursos), count (5 instancias), for_each con map y con toset, lifecycle create_before_destroy / prevent_destroy / ignore_changes |
| 04 Variables | 13 | defaults, prompt, -var, TF_VAR_, terraform.tfvars, -var-file, auto.tfvars, listas, maps, validation, sensitive (RDS), funcion file(); outputs y locals |
| 05 Datasources | 1 | data.aws_ami resolviendo la AMI vigente, con outputs de IP y DNS |

Pruebas que valen la pena recordar:
- `prevent_destroy` bloqueo el destroy con "Instance cannot be destroyed"; recien al quitar el meta-argumento se pudo destruir.
- En el lab de variables sensibles, el valor no aparece en los outputs pero **si figura en texto plano en terraform.tfstate**. Ese es el argumento para el backend remoto cifrado del lab 06.

## Lo que estaba roto en el material (10 clases de problema)

| Problema | Donde | Arreglo |
|---|---|---|
| `required_version = "~> 0.14"` | todos | `>= 1.0` + provider `~> 6.0` (helper `labs/modernizar.sh`) |
| AMI de 2020 caducados | todos los de EC2 | resueltos con `describe-images` en el runner |
| key pair `terraform-key` inexistente | 03-02 y otros | se usa `vockey`, que lo crea el Learner Lab |
| `vpc = true` en `aws_eip` | 03-02 | `domain = "vpc"` |
| `name` en `aws_db_instance` | 04-01 v10 | `db_name` (renombrado en el provider 4.x) |
| `db.t2.micro` con MySQL 8.4 | 04-01 v10 | `db.t3.micro`: AWS no soporta esa combinacion |
| `t3.xlarge` | 04-01 v7 | `t3.micro`: el Learner Lab deniega tipos grandes |
| nombres de SG empezando con `sg-` | adaptaciones | AWS los rechaza |
| `iam:CreateUser` denegado | 03-04 v2 | adaptado a Security Groups con el mismo `for_each = toset(...)` |
| SCP deniega `s3:GetBucketObjectLockConfiguration` | 03-04 v1, 04-03 | el bucket se crea pero el apply falla al releerlo; adaptado a Security Groups |

Los archivos originales de los labs adaptados quedaron con el sufijo
`.original-no-corre-en-learner-lab`, al lado de la version que si corre.

## Detalles de entorno

- Cache compartida de providers en `~/.terraform.d/plugin-cache` (via `~/.terraformrc`).
  Sin esto cada lab se bajaba su copia: habia acumulado **17 GB**.
- Hay que borrar `.terraform.lock.hcl` antes del `init` cuando se usa la cache compartida,
  o Terraform se queja de que los checksums no coinciden.
- Todo quedo **destruido**. El `terraform.tfstate` de cada carpeta es la evidencia de que corrio.

## Pendiente del T05

Secciones 06 a 10: State remoto, Workspaces, Provisioners, Modules y Terraform Cloud.
El lab 10-01 requiere crear una cuenta en HCP Terraform y conectarla a GitHub.
