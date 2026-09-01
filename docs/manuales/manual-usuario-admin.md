# Manual de Usuario — Administrador

> Guía de uso del sistema INCAF para el rol **Administrador**: acceso completo al sistema, incluyendo la gestión de usuarios, centros, configuración y reportes.

## 1. Qué puede hacer un Administrador

El Administrador tiene acceso a **todas** las secciones del sistema, sin restricciones. Además de las tareas clínicas y administrativas que comparte con los demás roles (pacientes, citas, admisiones, expedientes), el Administrador es el único rol que puede:

- Crear y editar cuentas de otros usuarios, incluyendo asignar el rol de Administrador.
- Gestionar los Centros Médicos del sistema.
- Cambiar la Configuración general del sistema (reglas de bloqueo de sesión, duración de sesiones, tamaño de archivos, etc.).
- Crear y editar las definiciones de Reportes y Paquetes ARS.
- Configurar el correo y WhatsApp del módulo Comunicaciones, y enviar avisos de prioridad "Alerta".
- Restaurar registros desactivados (pacientes, usuarios, etc.).
- Ver el registro de actividad completo de cualquier usuario.

## 2. Cómo iniciar sesión

1. Abra el navegador y vaya a la dirección del sistema que le indicó su equipo de TI (por ejemplo `https://192.168.1.42`).
2. Ingrese su **usuario** y **contraseña**.
3. Haga clic en **"Iniciar sesión"**.

> (TIP) Si la sesión se cierra por inactividad, vuelva a iniciar sesión con las mismas credenciales — no se pierde ningún dato pendiente que ya haya guardado.

## 3. Recorrido de la interfaz

El menú lateral izquierdo muestra, para el Administrador, todas las secciones agrupadas así:

- **Atención**: Admisiones, Pacientes, Citas, Expedientes.
- **Operación**: Médicos, Salas, Servicios, Medicamentos.
- **Red**: Centros Médicos, ARS.
- Al pie: Reportes, Comunicaciones, Usuarios, Configuración.

El panel principal (Dashboard) muestra un resumen: citas de hoy, total de pacientes, total de médicos y total de citas.

## 4. Tareas comunes paso a paso

### Crear un nuevo usuario

1. Vaya a **Usuarios** en el menú.
2. Haga clic en **"Nuevo"**.
3. Complete usuario, nombre, apellido, correo, rol y, si aplica, el centro (para el rol Gerente de centro).
4. Asigne una contraseña temporal y pida a la persona que la cambie en su primer ingreso.
5. Guarde.

### Desactivar o restaurar un usuario

1. Vaya a **Usuarios**, ubique la cuenta.
2. Use la opción **"Desactivar"** para revocar el acceso sin borrar su historial.
3. Para recuperarlo más tarde, active **"Mostrar inactivos"** en la parte superior de la lista, ubique la cuenta y use **"Restaurar"**.

### Desbloquear una cuenta

Si un usuario introdujo su contraseña incorrectamente varias veces, su cuenta queda bloqueada temporalmente. Vaya a **Usuarios**, ubique la cuenta (aparecerá marcada como bloqueada) y use la opción **"Desbloquear"**.

### Gestionar un Centro Médico

1. Vaya a **Centros Médicos**.
2. Use **"Nuevo"** para crear un centro, o seleccione uno existente para editarlo.
3. Complete nombre, código, dirección y teléfono.

### Cambiar ajustes generales del sistema

1. Vaya a **Configuración**.
2. Ajuste las reglas de sesión, bloqueo de cuentas, tamaño máximo de archivos, etc., según lo necesite.
3. Guarde — la mayoría de estos cambios aplican de inmediato, sin necesidad de reiniciar nada.

### Configurar Comunicaciones (correo y WhatsApp)

1. Vaya a **Comunicaciones → Ajustes**.
2. En la pestaña **Correo**, complete los datos del servidor de correo y use **"Enviar correo de prueba"** para confirmar.
3. En la pestaña **WhatsApp**, pegue las credenciales provistas por Meta, configure el tiempo de aviso previo a las citas, y active **"Activar WhatsApp a pacientes"**.
4. En **Comunicaciones → Plantillas**, active las plantillas de mensajes aprobadas por Meta antes de que cualquier WhatsApp pueda enviarse.

## 5. Qué NO puede hacer / a quién contactar

El Administrador no tiene restricciones dentro del sistema. Fuera del sistema, para tareas de servidor (instalar, respaldar, actualizar el sistema), consulte el **Manual de Despliegue** y el **Manual de Respaldo**, o contacte a la persona encargada de TI/infraestructura si el Administrador de la clínica no es la misma persona que administra el servidor.

## 6. Buenas prácticas de seguridad

- No comparta su usuario ni contraseña con nadie, incluyendo otros administradores — cada persona debe tener su propia cuenta para que el registro de auditoría sea confiable.
- Cierre sesión al terminar de usar una computadora compartida.
- Asigne el rol de Administrador solo a quien realmente lo necesite — es el rol con más alcance en el sistema.
- Revise periódicamente **Usuarios → Actividad** de las cuentas con más privilegios.
- Al desactivar a un empleado que deja la organización, hágalo el mismo día, no después.

## 7. Preguntas frecuentes

**¿Puedo tener más de un Administrador?**
Sí, no hay límite. Se recomienda tener al menos dos, para que el sistema no dependa de una sola persona.

**Un usuario olvidó su contraseña, ¿qué hago?**
Vaya a **Usuarios**, ubique la cuenta, use **"Cambiar contraseña"** para asignarle una nueva temporal, y pídale que la cambie en su próximo ingreso.

**¿Dónde veo qué hizo un usuario en el sistema?**
En **Usuarios**, seleccione la cuenta y abra su pestaña **"Actividad"** — muestra fecha, acción, y el registro afectado.

**¿Qué diferencia hay entre mi rol y el de Gerente de centro?**
El Gerente de centro tiene casi el mismo alcance que un Administrador, pero limitado a su propio centro asignado, y no puede cambiar la Configuración general del sistema ni las definiciones de Reportes.
