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

> (WARN) No ejecute una restauración (Capítulo 6) al mismo tiempo que un respaldo está en curso.

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

## 6. Restaurar desde un respaldo

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

> (WARN) No borre el archivo de respaldo que acaba de usar hasta confirmar (Capítulo 7) que la restauración funcionó correctamente.

## 7. Verificación posterior a la restauración

Después de restaurar y aplicar los dos pasos del Capítulo 6, confirme que todo quedó bien:

1. Inicie sesión en el sistema con una cuenta conocida.
2. Abra el expediente de un paciente que sepa que existía en el respaldo restaurado y confirme que sus datos se ven correctamente.
3. Revise que la fecha/hora de los registros más recientes coincida con lo esperado del respaldo restaurado (no con datos posteriores, que ya no deberían estar ahí).
4. Confirme que la verificación de salud del sistema responde correctamente:
   ```bash
   curl -k https://<IP-del-servidor>/api/health/
   ```

Solo después de confirmar estos cuatro puntos puede considerar la restauración exitosa y, si corresponde, archivar o limpiar respaldos antiguos con confianza.

## 8. Preguntas frecuentes

**¿Cada cuánto debo respaldar?**
Como mínimo, una vez al día mediante la tarea programada del Capítulo 4. Si el volumen de pacientes es alto, considere respaldar con más frecuencia (cada 6–12 horas).

**¿Dónde debo guardar la copia fuera del servidor?**
Cualquier lugar físicamente distinto al servidor: un disco externo que se retire del sitio, una carpeta de red en otro equipo, o un servicio de almacenamiento en la nube con cifrado y acceso restringido. Lo importante es que un problema con el servidor (robo, incendio, falla de disco) no afecte también a la copia.

**¿Qué hago si el script de respaldo falla?**
Lea el mensaje de error que muestra en pantalla — usualmente indica si el servicio `db` no está corriendo, o si no hay espacio en disco. Si no logra resolverlo, guarde el mensaje de error completo y contacte a su desarrollador o a TI antes de intentar una restauración con un respaldo que pueda estar incompleto.

**¿Puedo restaurar solo la base de datos sin las imágenes?**
Sí — omita el parámetro `-MediaArchive` al ejecutar `restore_db.ps1`. El script mostrará una advertencia recordando que las imágenes no se restauraron.

**¿Es seguro practicar una restauración antes de que haya una emergencia real?**
Sí, y se recomienda hacerlo periódicamente — es la única forma de confirmar que el respaldo realmente funciona antes de necesitarlo de verdad. Hágalo en un momento de bajo uso y avise al personal de antemano, ya que la restauración reemplaza los datos actuales durante la prueba.
