# Manual de Respaldo y Restauración

> Guía paso a paso para respaldar y restaurar los datos de MedicalConsultations, y cómo manejar los archivos que genera el respaldo, en Windows y en Linux.

## 1. Qué se respalda y qué no

Todos los datos del sistema — pacientes, expedientes, citas, encuentros, registro de auditoría, usuarios — viven en dos lugares dentro de Docker:

- La **base de datos** (`medicalconsultations_pgdata`): toda la información excepto las imágenes clínicas.
- El **volumen de archivos** (`medicalconsultations_media_volume`): las imágenes subidas a los expedientes.

Ninguno de los dos tiene respaldo automático propio dentro de Docker. Si el disco del servidor falla, si alguien ejecuta un comando destructivo, o si una actualización sale mal, **el único camino de recuperación es un respaldo hecho de antemano.**

> (NOTE) El sistema nunca borra datos de verdad cuando un usuario "elimina" un registro desde la aplicación (es un borrado suave, reversible desde adentro) — pero eso no reemplaza un respaldo. Un respaldo protege contra la pérdida del servidor completo, no contra errores de un usuario dentro del sistema.

## 2. Ejecutar un respaldo manualmente

**Windows:** abra PowerShell dentro de la carpeta `infra/` y ejecute:
```powershell
./scripts/backup_db.ps1
```

**Linux:** los scripts están escritos en PowerShell, que también corre en Linux mediante **PowerShell Core** (`pwsh`). Si aún no lo tiene instalado:
```bash
sudo apt-get update && sudo apt-get install -y wget apt-transport-https software-properties-common
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update && sudo apt-get install -y powershell
```
Luego ejecute el mismo script con `pwsh`:
```bash
cd infra
pwsh ./scripts/backup_db.ps1
```

**Qué hace este comando:**

1. Genera una copia completa de la base de datos.
2. Genera una copia comprimida de todas las imágenes subidas.
3. Guarda ambos archivos, con fecha y hora en el nombre, dentro de `infra/backups/`.
4. Borra automáticamente los respaldos más antiguos que 14 días (ajustable, ver abajo).

**Cómo confirmar que funcionó:** el script termina mostrando en pantalla el mensaje `Backup complete: ` seguido de la ruta del archivo. Revise que la carpeta `infra/backups/` tenga dos archivos nuevos con la fecha de hoy en el nombre.

**Opciones disponibles:**

| Opción | Por defecto | Para qué sirve |
|---|---|---|
| `-RetentionDays` | `14` | Días que se conservan los respaldos antes de borrarse automáticamente. Ejemplo: `./scripts/backup_db.ps1 -RetentionDays 30` |
| `-BackupDir` | `infra/backups` | Carpeta donde se guardan los respaldos. Ejemplo: `./scripts/backup_db.ps1 -BackupDir "D:\Respaldos"` |

> (NOTE) El sistema (el servicio `db`) debe estar corriendo para que el respaldo funcione. Si el sistema completo está apagado, inicie al menos la base de datos con `docker compose up -d db` antes de respaldar.

## 3. Qué NO hacer durante un respaldo

> (WARN) No interrumpa el script mientras está corriendo (no cierre la ventana de PowerShell ni apague la computadora) — puede dejar un archivo de respaldo incompleto y corrupto sin avisar.

> (WARN) No ejecute una restauración (Capítulo 7) al mismo tiempo que un respaldo está en curso.

> (WARN) No borre archivos `.dump` o `.tar.gz` manualmente desde la carpeta `infra/backups/` sin antes confirmar que no son el único respaldo disponible — el script ya limpia los respaldos viejos automáticamente según `-RetentionDays`; no hace falta borrar a mano salvo que se esté liberando espacio de forma deliberada.

## 4. Programar respaldos automáticos

Nada en el sistema programa respaldos automáticos por sí solo — hay que configurarlo una vez, manualmente, en el propio sistema operativo.

**Windows — Programador de tareas (Task Scheduler), paso a paso:**

1. Abra el menú Inicio, escriba **"Programador de tareas"** y ábralo.
2. En el panel derecho, haga clic en **"Crear tarea básica..."**.
3. Asígnele un nombre, por ejemplo `Respaldo MedicalConsultations`, y clic en **Siguiente**.
4. Elija **"Diariamente"** como frecuencia (o la que prefiera) y clic en **Siguiente**.
5. Elija la hora de inicio — se recomienda una hora de poco uso, por ejemplo 2:00 a.m. — y clic en **Siguiente**.
6. En "Acción", elija **"Iniciar un programa"** y clic en **Siguiente**.
7. En **"Programa o script"**, escriba: `pwsh.exe` (o `powershell.exe` si `pwsh` no está instalado).
8. En **"Agregar argumentos"**, escriba: `-File "C:\ruta\completa\a\infra\scripts\backup_db.ps1"` (reemplace la ruta por la real en su servidor).
9. Clic en **Siguiente**, revise el resumen, y clic en **Finalizar**.
10. Busque la tarea recién creada en la lista, haga clic derecho sobre ella y elija **"Ejecutar"** una vez, para confirmar que funciona sin errores antes de confiar en que corra sola cada noche.

> (TIP) Los 10 pasos anteriores también se pueden hacer con un solo comando: `infra/scripts/schedule_backup_task.ps1` (ejecutado como Administrador) registra la misma tarea diaria automáticamente — vea los comentarios del propio script para las opciones (`-At`, `-RetentionDays`, `-RunNow`).

**Linux — cron:**
```bash
crontab -e
```
Agregue esta línea para ejecutar el respaldo todas las noches a las 2:00 a.m.:
```
0 2 * * * pwsh /ruta/completa/a/infra/scripts/backup_db.ps1 >> /var/log/mc-backup.log 2>&1
```
Guarde y cierre el editor. El registro de cada ejecución quedará en `/var/log/mc-backup.log` — revíselo de vez en cuando para confirmar que sigue funcionando.

## 5. Manejo de los archivos generados

Cada respaldo produce dos archivos con fecha y hora en el nombre, por ejemplo:

```
pgdata_2026-08-21T140005.dump
media_2026-08-21T140005.tar.gz
```

> (DANGER) Estos archivos contienen los mismos datos personales de pacientes que la base de datos en vivo — trátelos con el mismo cuidado: solo personal autorizado debe tener acceso a la carpeta o unidad donde se guardan, nunca deben subirse a un repositorio de código, ni enviarse por correo o mensajería sin cifrar.

**Retención:** por defecto se conservan 14 días de respaldos; los más antiguos se borran automáticamente en cada ejecución (ajustable con `-RetentionDays`, ver Capítulo 2).

**Copiar los respaldos fuera del servidor.** Si el disco del servidor falla, los respaldos guardados ahí mismo se pierden con él. Es indispensable copiar `infra/backups/` a otro lugar periódicamente — un disco externo, una carpeta de red, o un almacenamiento en la nube. Esto no ocurre automáticamente; hágalo parte de una rutina.

**Windows** — copiar a una unidad de red o USB mapeada como una unidad (por ejemplo `E:\`):
```powershell
robocopy "infra\backups" "E:\RespaldosMedicalConsultations" /MIR
```
(`/MIR` sincroniza el destino para que sea un espejo exacto del origen; puede omitirlo si prefiere solo copiar sin borrar nada en el destino.)

**Linux** — copiar a una carpeta de red o servidor remoto vía `rsync`:
```bash
rsync -av infra/backups/ usuario@servidor-remoto:/ruta/RespaldosMedicalConsultations/
```
o vía `scp` para una copia simple:
```bash
scp infra/backups/*.dump infra/backups/*.tar.gz usuario@servidor-remoto:/ruta/RespaldosMedicalConsultations/
```

## 6. Enviar los respaldos a almacenamiento en la nube y rotación de credenciales

Copiar a un disco externo o carpeta de red (Capítulo 5) ya saca los respaldos del servidor, pero siguen dependiendo del mismo edificio — un incendio, un robo, o una inundación puede afectar ambos a la vez. Un almacenamiento en la nube (fuera del sitio) es la protección real contra ese escenario. Esta sección cubre tres formas de hacerlo, de más simple a más flexible, y cómo manejar las credenciales de forma segura una vez configurado.

> (NOTE) Que el proveedor de la nube cifre los datos "en reposo" (a lo interno, en sus propios discos) es una protección distinta de mantener las credenciales de acceso seguras. Un cifrado en reposo no sirve de nada si la cuenta o la clave de acceso se filtra — cualquiera con esa credencial puede simplemente descargar los respaldos ya descifrados por el proveedor. Por eso esta sección también cubre cómo rotar esas credenciales, no solo cómo subir los archivos.

### Opción A — Carpeta sincronizada (la más simple, sin necesidad de scripts)

Si ya tiene o puede instalar una aplicación de sincronización de escritorio (OneDrive, Google Drive, Dropbox), configure `infra/backups/` — o mejor, la carpeta de destino usada en el Capítulo 5 (`E:\RespaldosMedicalConsultations`, por ejemplo) — como una carpeta sincronizada. Todo lo que llegue ahí se sube automáticamente, sin escribir ningún comando.

- Ventaja: no requiere conocimientos técnicos adicionales; la aplicación queda corriendo en segundo plano.
- Desventaja: menos control sobre permisos y rotación de credenciales — depende de la seguridad de la cuenta personal/organizacional usada para la sincronización.

> (WARN) Si usa esta opción, la cuenta de sincronización debe ser una cuenta **organizacional dedicada** (de la clínica, con acceso restringido a IT/administración), nunca la cuenta personal de un empleado — si esa persona deja la clínica, sus respaldos no deben quedar ligados a una cuenta que ya no controla.

### Opción B — `rclone` (recomendado: funciona con casi cualquier proveedor)

[`rclone`](https://rclone.org/) es una herramienta gratuita y de código abierto que sube archivos a más de 40 proveedores de almacenamiento (Backblaze B2, Amazon S3, Google Drive, Azure Blob Storage, Dropbox, OneDrive, y otros) con el mismo conjunto de comandos, y guarda las credenciales en un archivo de configuración que puede protegerse con su propia contraseña.

1. Instale `rclone` (Windows: descargue el ejecutable desde rclone.org y agréguelo al PATH; Linux: `curl https://rclone.org/install.sh | sudo bash`).
2. Configure un "remoto" (la conexión al proveedor elegido):
   ```bash
   rclone config
   ```
   Siga el asistente interactivo — elija el proveedor, y pegue la clave de acceso (access key / API token) que генera ese proveedor para una cuenta o "bucket" dedicado a estos respaldos.
3. (Recomendado) Proteja el archivo de configuración de `rclone` con una contraseña propia, para que las credenciales guardadas no queden legibles si alguien copia ese archivo:
   ```bash
   rclone config set --obscure
   ```
   o, más simple, actívelo desde el mismo asistente de `rclone config` con la opción **"Set configuration password"**.
4. Suba los respaldos (ejecútelo después de `backup_db.ps1`, o agréguelo a la misma tarea programada del Capítulo 4):
   ```bash
   rclone sync infra/backups <nombre-del-remoto>:medicalconsultations-backups --create-empty-src-dirs
   ```
5. Verifique que los archivos llegaron:
   ```bash
   rclone lsl <nombre-del-remoto>:medicalconsultations-backups
   ```

> (TIP) Para empezar sin costo, **Backblaze B2** ofrece 10 GB gratis y es uno de los proveedores más simples de configurar con `rclone` — suficiente para varios meses de respaldos de una clínica pequeña antes de necesitar un plan pago.

### Opción C — Herramienta propia del proveedor (si la clínica ya usa uno específico)

Si la clínica ya tiene una cuenta empresarial con un proveedor específico, sus herramientas nativas también sirven y a veces se integran mejor con las políticas de esa cuenta (por ejemplo, retención automática, alertas):

- **Amazon S3:** `aws s3 sync infra/backups s3://<nombre-del-bucket>/medicalconsultations-backups`
- **Azure Blob Storage:** `azcopy sync "infra/backups" "https://<cuenta>.blob.core.windows.net/<contenedor>" --recursive`
- **Google Cloud Storage:** `gsutil -m rsync -r infra/backups gs://<nombre-del-bucket>/medicalconsultations-backups`

Cada una requiere instalar su propia herramienta de línea de comandos (`aws configure`, `az login`, `gcloud auth login`) y guarda sus credenciales de forma similar a `rclone` — la rotación de credenciales de esta sección aplica igual, solo cambia el comando para generar una clave nueva en el proveedor.

### Qué NO hacer al subir respaldos a la nube

> (DANGER) Nunca escriba la clave de acceso (access key, API token, contraseña) directamente dentro de un script `.ps1` o `.sh` que luego pueda quedar en una carpeta compartida, un repositorio, o un correo. `rclone`, `aws configure`, `az login` y `gcloud auth login` ya guardan las credenciales en su propio archivo de configuración local — use eso, no un valor pegado a mano en el script.

> (WARN) No use una cuenta de nube personal de un empleado para esto — use siempre una cuenta o "bucket" dedicado, propiedad de la clínica, con acceso limitado a quien de verdad lo necesite (idealmente solo permisos de **subida**, sin permiso de borrado, para que ni siquiera una credencial comprometida pueda destruir los respaldos ya guardados).

> (WARN) No confíe en que "el proveedor ya cifra los datos" como única protección — eso protege contra el robo físico de los discos del proveedor, no contra una credencial de acceso filtrada o un empleado que se va sin que se le revoque el acceso.

> (DANGER) No comparta la misma credencial entre varias personas o varios sistemas. Si necesita que más de una persona pueda subir o revisar respaldos, cree una credencial separada por persona/uso — así, revocar el acceso de una persona no interrumpe a las demás.

### Rotación de credenciales

Rotar significa: generar una credencial nueva, actualizar la configuración para usarla, confirmar que funciona, y **revocar la anterior** en el proveedor (no solo dejar de usarla — un token viejo sin revocar sigue siendo válido indefinidamente).

**Cuándo rotar:**
- Cada **90–180 días** como rutina, sin que tenga que pasar nada — trátelo igual que cambiar una contraseña importante.
- **Inmediatamente** si alguien con acceso a esa credencial deja la clínica, cambia de rol, o si sospecha que la credencial pudo haberse expuesto (por ejemplo, un script con la clave se compartió por error).

**Cómo rotar (con `rclone`, el método recomendado de la Opción B):**
1. En el panel del proveedor (Backblaze, AWS, etc.), genere una **clave de acceso nueva** — no edite la existente, cree una adicional.
2. Actualice el remoto en `rclone` con la clave nueva:
   ```bash
   rclone config update <nombre-del-remoto> access_key_id <NUEVA_CLAVE> secret_access_key <NUEVO_SECRETO>
   ```
3. Verifique que la clave nueva funciona antes de continuar:
   ```bash
   rclone lsd <nombre-del-remoto>:
   ```
4. Solo después de confirmar que funciona, **revoque/elimine la clave anterior** en el panel del proveedor.
5. Anote la fecha de esta rotación en algún lugar (una hoja de cálculo, un calendario recordatorio) para saber cuándo toca la próxima.

Para las opciones C (AWS/Azure/Google), el mismo principio aplica: genere la credencial nueva primero, confírmela, y solo después revoque la anterior — nunca al revés, para no quedarse sin poder subir respaldos mientras resuelve el problema.

> (WARN) No rote la credencial y revoque la anterior en el mismo paso sin haber confirmado primero que la nueva funciona — si la nueva credencial tiene un error de configuración, se queda sin forma de subir respaldos hasta corregirlo.

## 7. Restaurar desde un respaldo

> (DANGER) Restaurar **reemplaza por completo** la base de datos y los archivos actuales con los del respaldo elegido. Todo lo guardado después de la fecha de ese respaldo se pierde. Antes de restaurar sobre un sistema que está en uso real, ejecute primero un respaldo nuevo (Capítulo 2) por si necesita volver atrás.

**Windows:**
```powershell
./scripts/restore_db.ps1 -DumpFile "infra/backups/pgdata_2026-08-21T140005.dump" `
  -MediaArchive "infra/backups/media_2026-08-21T140005.tar.gz" -Confirm
```

**Linux:**
```bash
pwsh ./scripts/restore_db.ps1 -DumpFile "infra/backups/pgdata_2026-08-21T140005.dump" -MediaArchive "infra/backups/media_2026-08-21T140005.tar.gz" -Confirm
```

Reemplace los nombres de archivo por los del respaldo que quiere restaurar. El parámetro `-Confirm` es obligatorio a propósito — el script se niega a correr sin él, precisamente porque el efecto es destructivo. `-MediaArchive` es opcional: si se omite, solo se restaura la base de datos, sin las imágenes.

**Después de restaurar, siempre haga estos dos pasos:**

1. **Vuelva a aplicar las actualizaciones de base de datos ("migraciones"):**
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py migrate
   ```
2. **Revise la clave de cifrado (`PII_FIELD_KEY`).** Si esa clave cambió entre el momento del respaldo y ahora, los datos de pacientes restaurados quedan ilegibles hasta corregirlo. Use la clave que estaba activa cuando se hizo ese respaldo, o ejecute:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py reencrypt_pii --old-key <CLAVE_DE_ESE_MOMENTO>
   ```

> (WARN) Nunca restaure con la clave `PII_FIELD_KEY` equivocada esperando "arreglarlo después" — los datos de pacientes quedan permanentemente ilegibles bajo la clave incorrecta hasta ejecutar el paso de arriba con la clave correcta. Si no está seguro de cuál era la clave correcta en ese momento, deténgase y consulte a su desarrollador antes de continuar.

> (WARN) No borre el archivo de respaldo que acaba de usar hasta confirmar (Capítulo 8) que la restauración funcionó correctamente.

## 8. Verificación posterior a la restauración

Después de restaurar y aplicar los dos pasos del Capítulo 7, confirme que todo quedó bien:

1. Inicie sesión en el sistema con una cuenta conocida.
2. Abra el expediente de un paciente que sepa que existía en el respaldo restaurado y confirme que sus datos se ven correctamente.
3. Revise que la fecha/hora de los registros más recientes coincida con lo esperado del respaldo restaurado (no con datos posteriores, que ya no deberían estar ahí).
4. Confirme que la verificación de salud del sistema responde correctamente:
   ```bash
   curl -k https://<IP-del-servidor>/api/health/
   ```

Solo después de confirmar estos cuatro puntos puede considerar la restauración exitosa y, si corresponde, archivar o limpiar respaldos antiguos con confianza.

## 9. Preguntas frecuentes

**¿Cada cuánto debo respaldar?**
Como mínimo, una vez al día mediante la tarea programada del Capítulo 4. Si el volumen de pacientes es alto, considere respaldar con más frecuencia (cada 6–12 horas).

**¿Dónde debo guardar la copia fuera del servidor?**
Cualquier lugar físicamente distinto al servidor: un disco externo que se retire del sitio, una carpeta de red en otro equipo, o un servicio de almacenamiento en la nube con cifrado y acceso restringido. Lo importante es que un problema con el servidor (robo, incendio, falla de disco) no afecte también a la copia. Vea el Capítulo 6 para las opciones de nube y cómo manejar esas credenciales de forma segura.

**¿Qué hago si el script de respaldo falla?**
Lea el mensaje de error que muestra en pantalla — usualmente indica si el servicio `db` no está corriendo, o si no hay espacio en disco. Si no logra resolverlo, guarde el mensaje de error completo y contacte a su desarrollador o a TI antes de intentar una restauración con un respaldo que pueda estar incompleto.

**¿Puedo restaurar solo la base de datos sin las imágenes?**
Sí — omita el parámetro `-MediaArchive` al ejecutar `restore_db.ps1`. El script mostrará una advertencia recordando que las imágenes no se restauraron.

**¿Es seguro practicar una restauración antes de que haya una emergencia real?**
Sí, y se recomienda hacerlo periódicamente — es la única forma de confirmar que el respaldo realmente funciona antes de necesitarlo de verdad. Hágalo en un momento de bajo uso y avise al personal de antemano, ya que la restauración reemplaza los datos actuales durante la prueba.
