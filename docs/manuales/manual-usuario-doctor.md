# Manual de Usuario — Doctor/a

> Guía de uso del sistema INCAF para el rol **Doctor/a**: atención clínica de pacientes, expedientes médicos y admisiones.

## 1. Qué puede hacer un Doctor/a

El Doctor/a tiene acceso clínico completo:

- Ver y gestionar Pacientes (crear, editar).
- Ver y gestionar Admisiones (atender pacientes, admitir, completar).
- Ver y editar Expedientes Médicos — historial clínico, notas, imágenes.
- Ver y gestionar sus propias Citas y las del centro.
- Ver Médicos, Salas, Servicios, Medicamentos y ARS (consulta).
- Enviar avisos por correo a través de Comunicaciones.

No tiene acceso a Usuarios, Centros Médicos, Configuración ni Reportes — esas secciones ni siquiera aparecen en su menú.

## 2. Cómo iniciar sesión

1. Abra el navegador y vaya a la dirección del sistema indicada por su clínica.
2. Ingrese su **usuario** y **contraseña**.
3. Haga clic en **"Iniciar sesión"**.

## 3. Recorrido de la interfaz

El menú lateral del Doctor/a muestra:

- **Atención**: Admisiones, Pacientes, Citas, Expedientes.
- **Operación**: Médicos, Salas, Servicios, Medicamentos.
- **Red**: ARS.
- Al pie: Comunicaciones.

## 4. Tareas comunes paso a paso

### Admitir y atender a un paciente

1. Vaya a **Admisiones**.
2. Ubique al paciente en la lista del día, o cree una nueva admisión con **"Nuevo"** si aún no existe.
3. Complete el servicio, la sala y la prioridad, y use **"Admitir"** cuando el paciente esté listo para ser atendido.
4. Al finalizar la atención, use **"Completar"** en esa admisión.

### Completar un expediente médico

1. Vaya a **Expedientes** y ubique al paciente, o ábralo directamente desde su admisión con **"Abrir expediente"**.
2. Use **"Nuevo registro"** para agregar una nota clínica (diagnóstico, tratamiento, observaciones).
3. Si corresponde, suba imágenes clínicas con **"Subir imagen"**, agregando un título y descripción.
4. Guarde el registro — quedará asociado permanentemente al expediente del paciente.

### Registrar un paciente nuevo

1. Vaya a **Pacientes → Nuevo paciente**.
2. Complete identidad (nombre, cédula, fecha de nacimiento, género), contacto, y datos de seguro (ARS) si el paciente tiene uno.
3. Si es un paciente menor de edad, complete también la sección de tutor/responsable.
4. Guarde.

### Gestionar una cita

1. Vaya a **Citas**.
2. Use **"Nueva cita"** para agendar, o ubique una cita existente para **"Confirmar"**, **"Completar"** o **"Cancelar"**.
3. Al cancelar, el sistema pide un motivo — compleátelo brevemente.

### Enviar un aviso por correo

1. Vaya a **Comunicaciones**.
2. Use la opción de **redactar** un nuevo mensaje, seleccione destinatarios y escriba el contenido.
3. Envíe — el mensaje se procesa en segundo plano y aparecerá su estado (enviado, en cola, fallido) en la lista.

## 5. Qué NO puede hacer / a quién contactar

- No puede crear ni editar cuentas de otros usuarios — si necesita que se cree una cuenta o se desbloquee, contacte a Administración o TI.
- No puede ver ni editar Centros Médicos, Configuración del sistema, ni las definiciones de Reportes.
- No puede eliminar Admisiones ni Expedientes (esa acción está reservada a Administrador y Gerente de centro) — si un registro se creó por error, contacte a un Administrador.
- No puede enviar avisos de prioridad "Alerta" en Comunicaciones (solo mensajes de correo normales).

## 6. Buenas prácticas de seguridad

- No comparta su usuario ni contraseña, ni siquiera con otro médico del mismo centro.
- Cierre sesión al terminar de usar una computadora compartida entre varios médicos.
- Verifique siempre que está abriendo el expediente del paciente correcto antes de escribir una nota clínica — use la cédula, no solo el nombre, para confirmar identidad en caso de nombres similares.
- Los datos personales de los pacientes están protegidos por ley — no los comparta ni los muestre en pantalla a personas ajenas a la atención del paciente.

## 7. Preguntas frecuentes

**¿Puedo editar una nota clínica después de guardarla?**
Depende del estado del registro — consulte con Administración si necesita corregir algo después de completado, ya que algunos estados quedan protegidos contra edición para mantener la integridad del expediente.

**¿Por qué no veo la sección de Reportes?**
Esa sección está reservada a Administrador, TI y Gerente de centro. Si necesita un reporte específico, solicítelo a Administración.

**Un paciente tiene ARS pero un servicio no está cubierto, ¿cómo lo registro?**
Al registrar el servicio dentro de la admisión, marque (o deje sin marcar, según corresponda) la cobertura ARS de esa línea específica — el sistema clasifica cada servicio de forma independiente para efectos de reportes, sin importar si el paciente tiene ARS en general.

**¿Qué hago si me equivoco al admitir un paciente?**
Contacte a un Administrador o Gerente de centro — ellos pueden corregir o eliminar registros que un Doctor/a no puede modificar directamente.
