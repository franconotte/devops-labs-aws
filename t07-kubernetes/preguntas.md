# T07 Kubernetes — las preguntas de los labs, respondidas

## Parte 4: "¿Qué pasó con el POD?"

El lab hace crear un pod suelto con `kubectl run`, después borrarlo, y listar de nuevo.

**No vuelve.** Y esa es toda la lección: un Pod creado directamente no tiene quien lo cuide.
Es el objeto más básico de Kubernetes y nadie se hace responsable de su ciclo de vida.

Con un **Deployment** pasa lo contrario. El Deployment crea un ReplicaSet, y el ReplicaSet
tiene un trabajo único: que la cantidad de pods vivos coincida con `replicas`. Si borrás uno,
en segundos aparece otro con nombre nuevo.

Es exactamente el mismo patrón que el **Auto Scaling Group** del T04 y que el **service** de
ECS del T06: un controlador que compara estado deseado contra estado real y corrige la
diferencia. Kubernetes lo llama *reconciliation loop*, y es la idea central de todo el sistema.

## Parte 5, pregunta 1: ¿Qué pasa con un `initialDelaySeconds` muy bajo en la readinessProbe?

El pod queda marcado como **no listo** apenas arranca, porque la app todavía no terminó de
levantar y el chequeo falla. Consecuencias:

- El Service **no le manda tráfico** hasta que pase un chequeo exitoso.
- Durante un rollout, Kubernetes espera a que los pods nuevos estén *ready* antes de bajar los
  viejos. Si nunca llegan, **el despliegue se traba**.

No es catastrófico —la readiness no reinicia nada— pero retrasa todo. El valor correcto es
"cuánto tarda mi app en atender el primer request", medido, no adivinado.

El caso **realmente peligroso es el inverso**: un `initialDelaySeconds` bajo en la
**livenessProbe**. Ahí Kubernetes concluye que la app está colgada, **reinicia el contenedor**,
el nuevo tampoco llega a tiempo, y entrás en un bucle de reinicios: `CrashLoopBackOff`.
Por eso el lab pone la liveness en 15s y la readiness en 30s.

## Parte 5, pregunta 2: ¿Cuándo conviene liveness pero no readiness?

Cuando el proceso **no recibe tráfico de un Service**, así que no tiene sentido sacarlo de
un balanceo que no existe, pero sí querés que se reinicie si se cuelga:

- **Workers que consumen una cola** (SQS, RabbitMQ, Kafka). Nadie les hace requests; si el loop
  se traba, la única salida es reiniciar.
- **Procesos batch de larga duración** o cron jobs que corren adentro de un pod.
- **Sidecars** que exportan métricas o rotan logs.

La regla práctica: **readiness responde "¿te mando tráfico?"** y **liveness responde
"¿te reinicio?"**. Si nadie te manda tráfico, la primera pregunta no aplica.

Y el error clásico es al revés: poner **solo liveness** en una app web. Mientras arranca,
Kubernetes la mata por no responder, y nunca llega a estar lista.
