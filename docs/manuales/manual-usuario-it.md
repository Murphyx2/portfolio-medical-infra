# Manual de Usuario — TI

> Guía de uso del sistema INCAF para el rol **TI**: soporte técnico, gestión de usuarios y catálogos, sin acceso a datos clínicos ni a información personal completa de pacientes.

## 1. Qué puede hacer TI

El rol TI apoya la operación técnica del sistema, no la atención clínica:

- Crear, editar, desbloquear y restablecer contraseñas de Usuarios.
- Ver Pacientes, Admisiones, Citas — con los datos personales **enmascarados** (ver nota abajo).
- Gestionar Médicos (perfiles), Salas, Servicios y Medicamentos.
- Ver Configuración del sistema (sin poder editarla, salvo el Administrador).
- Ver y **crear/editar** las definiciones de Reportes y Paquetes ARS.

> (NOTE) TI ve los datos personales de los pacientes (nombre completo, cédula, teléfono, dirección) **ocultos o parcialmente enmascarados** en pantalla. Esto es intencional, no un error — TI necesita administrar el sistema sin tener acceso innecesario a información médica sensible.

## 2. Cómo iniciar sesión

1. Abra el navegador y vaya a la dirección del sistema indicada por su clínica.
2. Ingrese su **usuario** y **contraseña**.
3. Haga clic en **"Iniciar sesión"**.

## 3. Recorrido de la interfaz

El menú lateral de TI muestra:

- **Atención**: Admisiones, Pacientes, Citas. (Sin Expedientes.)
- **Operación**: Médicos, Salas, Servicios, Medicamentos.
- **Red**: ARS. (Sin Centros Médicos.)
- Al pie: Reportes, Usuarios, Configuración. (Sin Comunicaciones.)

## 4. Tareas comunes paso a paso

### Crear un usuario nuevo

1. Vaya a **Usuarios → Nuevo**.
2. Complete usuario, nombre, apellido, correo y rol.
3. Asigne una contraseña temporal y comuníquela de forma segura a la persona (nunca por un canal no cifrado si contiene datos sensibles).
4. Guarde.

### Restablecer una contraseña

1. Vaya a **Usuarios**, ubique la cuenta.
2. Use **"Cambiar contraseña"**, asigne una nueva contraseña temporal.
3. Pida a la persona que la cambie en su próximo ingreso.

### Desbloquear una cuenta

Si un usuario quedó bloqueado por varios intentos fallidos de inicio de sesión, vaya a **Usuarios**, ubique la cuenta y use **"Desbloquear"**.

### Gestionar el perfil de un médico

1. Vaya a **Médicos**.
2. Cree uno nuevo o edite uno existente: número de licencia, teléfono de contacto, servicios que ofrece, salas asignadas.
3. Guarde.

### Crear o editar una definición de Reporte

1. Vaya a **Reportes**.
2. Use **"Nueva definición"** (o edite una existente) para configurar un reporte de servicios prestados, o **"Nuevo paquete"** para un paquete ARS.
3. Guarde — los usuarios con acceso a Reportes podrán generarlo desde ese momento.

## 5. Qué NO puede hacer / a quién contactar

- No puede ver los datos personales completos de los pacientes (esto es intencional, no una falla) — si necesita confirmar un dato específico por una razón de soporte legítima, coordine con un Administrador o Doctor/a.
- No puede ver ni entrar al módulo de Comunicaciones en absoluto.
- No puede ver ni editar Expedientes Médicos.
- No puede ver ni gestionar Centros Médicos.
- No puede cambiar la Configuración general del sistema (solo puede verla) — los cambios de configuración los hace un Administrador.

## 6. Buenas prácticas de seguridad

- No comparta su usuario ni contraseña, incluso con otros miembros del equipo de TI.
- Al crear una cuenta nueva, use siempre una contraseña temporal única — nunca reutilice la misma para varias cuentas.
- Recuerde que aunque usted no ve los datos personales completos de los pacientes en pantalla, sigue siendo responsable de proteger el acceso al sistema y al servidor — consulte el Manual de Despliegue para las prácticas de seguridad de red e infraestructura.
- Documente cualquier cambio de configuración importante fuera del sistema (quién lo pidió, cuándo, por qué), ya que usted puede verla pero no editarla directamente.

## 7. Preguntas frecuentes

**¿Por qué no veo el nombre completo o la cédula de un paciente?**
Es el diseño intencional del sistema: TI administra cuentas y catálogos, no atiende pacientes, así que no necesita ver sus datos personales completos. Esto protege la privacidad del paciente incluso frente a quienes tienen acceso técnico al sistema.

**Necesito confirmar un dato de un paciente para resolver un problema técnico, ¿cómo lo hago?**
Pida a un Administrador, Doctor/a o Recepcionista que confirme el dato por usted, o que le indique el identificador interno del registro en vez del dato personal.

**¿Por qué no veo el módulo de Comunicaciones?**
Es una decisión de diseño del sistema — el módulo de Comunicaciones (correo y WhatsApp a pacientes) está fuera del alcance del rol TI por completo.

**¿Puedo cambiar la Configuración del sistema si es urgente?**
No directamente desde la interfaz — esa acción está reservada al rol Administrador. Si es urgente, contacte a un Administrador disponible.
