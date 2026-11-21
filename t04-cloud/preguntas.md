# T04 — Respuestas a las secciones "Para discutir en grupo"

Estas son las preguntas conceptuales de los labs. Se pueden responder sin tener AWS abierto;
al hacer el lab solo queda verificar que los números coincidan.

## Lab 1 — Dos instancias EC2 en distintas AZ

**1. ¿Qué IP privada tiene cada instancia?**
Cada una recibe una IP del rango de **su subnet**. En la VPC por defecto, cada AZ tiene su
propia subnet `/20` dentro de `172.31.0.0/16`: por ejemplo `172.31.16.x` en `us-east-1a` y
`172.31.32.x` en `us-east-1b`. El script `01-ec2-dos-instancias.sh` las imprime en una tabla.

**2. ¿Por qué son IPs de redes distintas si están en la misma cuenta?**
Porque una **subnet no cruza zonas de disponibilidad**. La VPC tiene un rango grande y lo
reparte en subnets, una por AZ, cada una con su bloque CIDR. Las instancias toman la IP de la
subnet donde nacieron, y por eso caen en redes distintas aunque compartan VPC y cuenta.
Esa separación es lo que permite que una AZ se caiga sin arrastrar a la otra.

**3. ¿Funciona el ping entre las dos instancias?**
**Por defecto no.** Y no es por las AZ: el enrutamiento dentro de la VPC ya las conecta. Falla
porque el **Security Group** solo permite el puerto 22, y el ping usa **ICMP**, que es otro
protocolo. Para que funcione hay que agregar una regla de entrada de tipo *All ICMP - IPv4*
con origen el propio SG:

```bash
aws ec2 authorize-security-group-ingress --group-id <sg-id> \
  --protocol icmp --port -1 --source-group <sg-id>
```

Detalle importante: los Security Groups son **con estado** (si permitís la ida, la vuelta está
permitida) y **solo tienen reglas de permiso**. Las Network ACLs, en cambio, son sin estado y
sí admiten reglas de denegación.

## Lab de VPC — Security Groups vs Network ACLs

| | Security Group | Network ACL |
|---|---|---|
| Dónde aplica | a la interfaz de red de la instancia | a toda la subnet |
| Estado | **stateful**: la respuesta vuelve sola | **stateless**: hay que permitir ida y vuelta |
| Reglas | solo *allow* | *allow* y *deny* |
| Evaluación | todas las reglas juntas | por número de regla, de menor a mayor, y se corta en la primera que coincide |

Por eso se usan juntos: el SG como control fino por instancia, y la NACL como barrera gruesa
de la subnet (por ejemplo, bloquear una IP atacante para toda la red).

## Lab de S3 — ¿por qué el sitio daba 403 antes de la policy?

Desactivar *Block Public Access* solo **habilita la posibilidad** de hacer el bucket público;
no otorga permisos. Mientras no exista una **bucket policy** con `s3:GetObject` para
`Principal: "*"`, cada archivo sigue siendo privado y el endpoint del sitio responde **403**.
Son dos capas distintas: una destraba, la otra concede.

## Lab de RDS — ¿por qué `Public access: No`?

La base no necesita estar en internet: se la consulta desde las EC2 de la misma VPC. Dejarla
privada reduce la superficie de ataque, y el acceso se controla con el Security Group,
permitiendo el **3306 solo desde el SG de las instancias**, no desde un rango de IPs. Así,
cualquier instancia que entre a ese grupo queda habilitada sin tocar reglas.

## Sobre la limpieza de recursos

Todos los labs terminan con una sección de limpieza, y conviene respetarla aunque los créditos
del Learner Lab sean gratis:

- Una **instancia RDS** olvidada consume créditos todo el tiempo, aunque nadie la use.
- Un **Elastic IP** sin asociar también se cobra.
- Los recursos de red tienen dependencias: no se puede borrar una VPC si quedan instancias,
  subnets o el Internet Gateway asociados. De ahí el orden de los comandos de limpieza.
