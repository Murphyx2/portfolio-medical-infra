# Manual de Usuario — Gerente de Centro

> Guía de uso del sistema INCAF para el rol **Gerente de centro**: alcance equivalente a Administrador, limitado a su centro médico asignado.

## 1. Qué puede hacer un Gerente de centro

El Gerente de centro tiene un alcance casi idéntico al de Administrador, con dos diferencias importantes:

- Está limitado a su **centro médico asignado** — por ejemplo, al generar Reportes, solo ve datos de su propio centro.
- **No puede editar la Configuración general del sistema** (solo verla) — salvo el ajuste de idioma, que sí puede cambiar.

Dentro de esos límites, puede:

- Gestionar Pacientes, Admisiones, Expedientes, Citas — con los mismos permisos que un Administrador, incluyendo eliminar registros.
- Gestionar Usuarios: crear, editar, desbloquear, restablecer contraseñas, e incluso asignar el rol de Administrador.
- Gestionar Centros Médicos, ARS, Médicos, Salas, Servicios y Medicamentos.
- Ver y generar Reportes de su centro (no puede crear ni editar las definiciones de reporte — eso es exclusivo de Administrador y TI).
- Ver y usar Comunicaciones (correo y recordatorios), aunque no configurar sus ajustes (Ajustes/Plantillas son exclusivos de Administrador).

## 2. Cómo iniciar sesión

1. Abra el navegador y vaya a la dirección del sistema indicada por su clínica.
2. Ingrese su **usuario** y **contraseña**.
3. Haga clic en **"Iniciar sesión"**.

## 3. Recorrido de la interfaz

El menú lateral del Gerente de centro muestra prácticamente todo lo que ve un Administrador:

- **Atención**: Admisiones, Pacientes, Citas, Expedientes.
- **Operación**: Médicos, Salas, Servicios, Medicamentos.
- **Red**: Centros Médicos, ARS.
- Al pie: Reportes, Comunicaciones, Usuarios, Configuración (solo lectura, salvo idioma).

## 4. Tareas comunes paso a paso

### Aprobar la vinculación de un médico a su centro

1. Vaya a **Médicos**, seleccione el médico correspondiente.
2. En la sección de salas/servicios asignados a ese médico en su centro, confirme o ajuste la vinculación.
3. Guarde.

### Generar un reporte de su centro

1. Vaya a **Reportes**.
2. Seleccione la definición de reporte (por ejemplo "Servicios prestados"), el mes, y confirme que el centro mostrado es el suyo (el sistema lo fuerza automáticamente a su centro asignado).
3. Use **"Generar"** para descargar el archivo.

### Gestionar usuarios de su centro

1. Vaya a **Usuarios → Nuevo** (o edite uno existente).
2. Complete los datos y asigne el rol correspondiente (Doctor/a, Enfermero/a, Recepcionista, etc.).
3. Guarde.

### Cambiar el idioma del sistema

1. Vaya a **Configuración**.
2. En la sección de idioma, seleccione el idioma preferido.
3. Guarde — este es el único campo de Configuración que puede modificar; el resto aparece visible pero no editable.

### Gestionar un paciente, admisión o cita (igual que Administrador)

Siga los mismos pasos que en el Manual de Usuario — Administrador (Capítulo 4) para Pacientes, Admisiones, Expedientes y Citas — el Gerente de centro tiene el mismo alcance en estas secciones.

## 5. Qué NO puede hacer / a quién contactar

- No puede editar la Configuración general del sistema (reglas de sesión, bloqueo, tamaño de archivos) — solo verla. Si necesita un cambio, contacte a un Administrador.
- No puede crear ni editar las definiciones de Reportes ni Paquetes ARS — solo generarlos y descargarlos. Si necesita un reporte nuevo que no existe, solicítelo a Administración o TI.
- No puede configurar los Ajustes de Comunicaciones (correo/WhatsApp) ni las Plantillas — solo Administrador puede hacerlo.
- Los datos y reportes que ve están limitados a su centro asignado — si necesita información de otro centro, contacte a un Administrador.

## 6. Buenas prácticas de seguridad

- No comparta su usuario ni contraseña — su cuenta tiene privilegios amplios, incluyendo la capacidad de crear otras cuentas de Administrador.
- Revise periódicamente la actividad de los usuarios de su centro desde **Usuarios → Actividad**.
- Al desactivar a un empleado que deja su centro, hágalo el mismo día.
- Cierre sesión al terminar de usar una computadora compartida.

## 7. Preguntas frecuentes

**¿Por qué solo veo datos de mi propio centro en Reportes?**
Es el diseño intencional del sistema — el Gerente de centro administra su propio centro, no toda la red de centros. Si necesita ver otro centro, contacte a un Administrador.

**¿Puedo asignar el rol de Administrador a alguien?**
Sí, el Gerente de centro puede asignar cualquier rol, incluyendo Administrador, al crear o editar un usuario.

**¿Por qué la Configuración aparece pero no puedo cambiar casi nada ahí?**
Es intencional — puede verla para tener contexto, pero solo un Administrador puede modificar las reglas generales del sistema. El único campo editable para usted es el idioma.

**¿Cuál es la diferencia real entre mi rol y Administrador?**
Solo dos: usted está limitado a su centro asignado en los reportes, y no puede editar la Configuración general del sistema ni las definiciones de Reportes. En todo lo demás, su alcance es equivalente.
