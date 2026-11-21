# T04 — Cloud, los 14 labs resueltos y listos para ejecutar

Cada lab del T04 está acá: como script ejecutable si se puede automatizar, o como guía
paso a paso si va sí o sí por consola. Todos traen su limpieza.

## Mapa completo

| Lab del curso | Acá | Modo |
|---|---|---|
| 01-IaaS/1 — EC2 en dos AZ | `01-ec2-dos-instancias.sh` | script |
| 01-IaaS/2 — ALB | `06-alb.sh` | script |
| 01-IaaS/3 — Auto Scaling Group | `07-asg-y-ami.sh asg` | script |
| 01-IaaS/4 — user-data y AMI custom | `07-asg-y-ami.sh ami` | script |
| 01-IaaS/5 — AWS CLI | `00-configurar-cli.sh` + `10-instancia-desde-cli.sh` | script |
| 01-IaaS/6 — Windows por RDP | `09-consola-windows-e-integrador.md` | consola |
| 01-IaaS/7 — Integrador | `09-consola-windows-e-integrador.md` | mixto |
| 02-networking/1 — VPC por consola | `02-vpc-cli.sh` (mismos recursos) | script |
| 02-networking/2 — VPC por CLI | `02-vpc-cli.sh` | script |
| 02-networking/3 — Subnets públicas y privadas | `08-subnets-publicas-privadas.sh` | script |
| 03-storage/1 — EFS por consola | `04-efs-cli.sh` (mismos recursos) | script |
| 03-storage/3 — EFS por CLI | `04-efs-cli.sh` | script |
| 03-storage/4 — S3 sitio estático | `03-s3-sitio-estatico.sh` | script · **ya probado en LocalStack** |
| 04-RDS — MySQL gestionado | `05-rds.sh` | script |
| Secciones "Para discutir" | `preguntas.md` | respondidas |

## Orden recomendado

```bash
bash 00-configurar-cli.sh            # instala la CLI y explica las credenciales
bash 10-instancia-desde-cli.sh       # el ejercicio del lab 5: instancia + SG puerto 80
bash 01-ec2-dos-instancias.sh        # EC2 en dos AZ  (clave y SG que reusan los demás)
bash 06-alb.sh                       # balanceador
bash 07-asg-y-ami.sh ami             # user-data + AMI custom
bash 07-asg-y-ami.sh asg             # launch template + ASG
bash 02-vpc-cli.sh                   # VPC propia
bash 08-subnets-publicas-privadas.sh # pública/privada + NAT + bastion
bash 04-efs-cli.sh                   # filesystem compartido
bash 05-rds.sh crear                 # base gestionada
bash 03-s3-sitio-estatico.sh         # sitio estático
```

**Limpiá entre lab y lab**: casi todos aceptan `limpiar` como argumento, y respetan el orden
de dependencias que exige AWS.

## Qué necesita cada cosa

- **Credenciales del Learner Lab** para todo, menos el lab de S3.
- **Nada** para el lab de S3: corre contra LocalStack.
  ```bash
  cd localstack && docker compose up -d
  cd .. && USAR_LOCALSTACK=1 bash 03-s3-sitio-estatico.sh
  ```

## Decisiones que tomé, distintas de las guías

| Qué | Por qué |
|---|---|
| SSH abierto **solo desde tu IP** | las guías usan `0.0.0.0/0`, que deja el puerto 22 expuesto a internet |
| En RDS, 3306 **desde el SG de las EC2** | más seguro y más simple que mantener rangos de IP |
| La password de RDS se pide por teclado | no queda en el script ni en el historial de bash |
| AMI buscada dinámicamente | los IDs de AMI de las guías (`ami-0533f2...`) caducan |
| IDs guardados en archivos `ids-*.env` | sin eso, limpiar es a mano y se olvidan recursos |

## Avisos

- Las credenciales del Learner Lab **caducan** al cerrar la sesión. Si ves `ExpiredToken`,
  corré `aws configure` de nuevo con las nuevas.
- El **NAT Gateway** y la instancia **RDS** consumen créditos por hora aunque no los uses.
  Son los dos recursos que más conviene no olvidarse prendidos.
- Varias guías usan el key pair **`vockey`**, que lo crea el propio Learner Lab. Mis scripts
  crean uno propio (`lab-t04-key`) para no depender de eso.
