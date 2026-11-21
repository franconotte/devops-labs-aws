# Los dos labs que van sí o sí por consola

El resto del T04 lo resuelven los scripts. Estos dos no conviene scriptearlos: uno
necesita un cliente gráfico y el otro es un ejercicio de diseño.

---

## Lab 6 — Instancia Windows (RDP)

**Por qué a mano:** la contraseña del Administrator la descifra la consola con tu `.pem`,
y la conexión es por escritorio remoto.

### Pasos

1. `EC2 > Launch instance`
   - Nombre: `test-instance-windows01`
   - AMI: buscar **Microsoft Windows Server 2022 Base**
   - Tipo: **t2.medium** (Windows no arranca cómodo en micro)
   - AZ: `us-east-1a`
   - Key pair: **`vockey`** ← el que ya trae el Learner Lab
   - Security Group: **RDP (TCP 3389) desde tu IP**, nunca desde `0.0.0.0/0`
2. Esperar a **2/2 checks passed**. Windows tarda bastante más que Linux.
3. Seleccionar la instancia → **Connect → RDP client → Get password**
4. Subir el `.pem` de `vockey` → **Decrypt password** → copiar la contraseña
5. Descargar el `.rdp` y conectarse con usuario `Administrator`
   - En Windows: Conexión a Escritorio remoto (viene con el sistema)
   - En Linux: `xfreerdp /u:Administrator /v:<IP_PUBLICA>` o Remmina

### Si no aparece la contraseña

Las dos causas del *Spoiler Alert* del lab:
- el key pair elegido no es `vockey`
- la instancia tiene menos de 4 minutos corriendo: Windows todavía no la generó

### Para discutir

- **Tiempo de arranque:** Windows tarda varios minutos en estar listo contra el minuto de
  una Amazon Linux. Arranca más servicios y corre el *sysprep* inicial.
- **SSH vs RDP:** SSH usa tu clave privada directo contra el servicio; en RDP la clave
  solo sirve para **descifrar** la contraseña que AWS generó, y después te autenticás con
  usuario y contraseña. Por eso el `.pem` se sube a la consola en vez de usarse al conectar.
- **Cuándo justifica Windows:** aplicaciones .NET Framework viejas, SQL Server con licencia
  Windows, Active Directory, o software que solo existe para Windows.

### Limpieza
`EC2 > Instances` → terminar la instancia, y borrar el Security Group de RDP.

---

## Lab 7 — Ejemplo integrador

Junta todo el módulo. **Parte A** es pública; **parte B** mete las instancias en subnets privadas.

### Parte A — arquitectura pública

```
Internet → ALB (subnets públicas 1a y 1b) → ASG con 2 instancias (AMI custom del lab 4)
```

Ya tenés las piezas scripteadas, en este orden:

```bash
bash 02-vpc-cli.sh                 # VPC dedicada con dos subnets públicas
bash 07-asg-y-ami.sh ami           # instancia con user-data
# cuando la web responda:
aws ec2 create-image --instance-id <id> --name html-web-ami --region us-east-1
bash 07-asg-y-ami.sh asg           # Launch Template + ASG usando esa AMI
bash 06-alb.sh                     # ALB + Target Group
```

Lo que falta unir a mano: enganchar el **ASG al Target Group**, que es un comando:

```bash
aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name asg-devops \
  --target-group-arns <TG_ARN> --region us-east-1
```

**Verificación:** entrar al DNS del ALB y refrescar. El `Instance ID` tiene que alternar.

### Parte B — instancias en subnets privadas

```
Internet → IGW → [subnet pública: ALB + Bastion + NAT GW]
                 [subnet privada: instancias del ASG] → NAT GW → Internet (solo salida)
```

Eso es exactamente lo que arma `08-subnets-publicas-privadas.sh`. Para completar la parte B:

1. Correr ese script (crea VPC, 4 subnets, IGW, NAT, bastion y una instancia privada)
2. Mover el ASG a las **subnets privadas**:
   ```bash
   aws autoscaling update-auto-scaling-group --auto-scaling-group-name asg-devops \
     --vpc-zone-identifier "<SUB_PRIV1>,<SUB_PRIV2>" --region us-east-1
   ```
3. Dejar el **ALB en las subnets públicas** apuntando al mismo Target Group
4. Entrar a las instancias privadas **solo por el bastion**

### Lo que hay que poder explicar

- **Por qué las privadas no tienen IP pública:** no se las puede alcanzar desde internet, y
  eso es el punto. Salen a internet por el NAT para bajar paquetes, pero nadie entra.
- **Por qué el ALB sí va en subnets públicas:** es el único que recibe tráfico de afuera.
- **Para qué el bastion:** es la única puerta de entrada por SSH, y así auditás un solo punto.
- **Por qué el NAT Gateway va en una subnet pública:** necesita salida real a internet por
  el IGW; si lo ponés en la privada, no tiene por dónde salir.

### Limpieza, en este orden

El lab lo aclara y vale respetarlo, porque las dependencias bloquean el borrado:

1. Auto Scaling Group
2. ALB y Target Group
3. **NAT Gateway** ← consume créditos por hora aunque nadie lo use
4. Bastion y demás instancias
5. Elastic IP del NAT
6. Subnets, route tables, IGW
7. VPC

Los scripts `limpiar` ya respetan ese orden.
