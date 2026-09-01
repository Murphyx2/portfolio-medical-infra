# Manual de Despliegue

> Guía paso a paso para instalar MedicalConsultations en un servidor dentro de la red privada de la clínica (no en internet pública), preparada para personal sin experiencia previa en Docker o en la línea de comandos. Cubre Windows 10, Windows 11, Windows Server y Linux.

## 1. Alcance: qué es y qué NO es este despliegue

Este sistema se instala para funcionar **dentro de la red local de la clínica** (la misma red Wi-Fi o cableada de la oficina) — nunca directamente expuesto a internet. Cualquier computadora o teléfono conectado a esa misma red podrá abrir la aplicación desde su navegador; nadie fuera de esa red podrá alcanzarla.

> (NOTE) "Red privada" significa: el servidor y todos los equipos que lo usan están en la misma red (la misma oficina, el mismo edificio, o una VPN que se comporte como tal). Ningún paso de este manual abre el sistema a internet ni requiere abrir puertos en el router/módem hacia afuera. Si en el futuro se necesita acceso público real, eso requiere trabajo adicional (dominio propio, certificado real, revisión de seguridad) fuera del alcance de este manual — no lo improvise siguiendo estos pasos.

**Lo que necesita antes de empezar:**

- Una computadora que sirva de **servidor** y se mantenga encendida (puede ser una PC reutilizada o un servidor dedicado).
- Acceso de **administrador** en esa computadora.
- Las tres carpetas del proyecto — `backend`, `frontend`, `infra` — copiadas al servidor, una junto a la otra dentro de una misma carpeta.
- Entre 30 y 90 minutos, y unos 4 GB de espacio libre en disco.

```
MedicalConsultations/
├── backend/
├── frontend/
└── infra/        <- todos los comandos de este manual se ejecutan desde aquí
```

> (TIP) Cada comando de este manual está listo para copiar y pegar tal cual, excepto donde aparece algo entre `<corchetes angulares>` — eso hay que reemplazarlo por su propio valor (por ejemplo, la contraseña o la dirección IP del servidor).

## 2. Instalación de Docker según el sistema operativo

La aplicación corre dentro de **Docker**, una herramienta que empaqueta la base de datos, el backend y el sitio web en piezas aisladas ("contenedores") para no tener que instalar cada programa a mano. Elija su sistema operativo:

### Windows 10 / Windows 11

1. Descargue **Docker Desktop** desde docker.com (o pida a la persona encargada de TI que lo instale).
2. Ejecute el instalador. Cuando pregunte por el "backend", deje marcada la opción **WSL 2** (viene así por defecto).
3. Reinicie la computadora si el instalador lo pide.
4. Abra Docker Desktop una vez — debe quedar corriendo en segundo plano (ícono de la ballena en la barra de tareas) para que los pasos siguientes funcionen.
5. Abra PowerShell y confirme la instalación:
   ```powershell
   docker --version
   docker compose version
   ```
   Ambos deben mostrar un número de versión, no un error.

### Windows Server (2019 / 2022)

Windows Server normalmente **no trae Docker Desktop** (esa versión con interfaz gráfica es para Windows de escritorio). En un servidor se instala **Docker Engine** directamente:

1. Habilite el rol de contenedores y, si el servidor lo soporta, **WSL 2** (o el rol Hyper-V como alternativa):
   ```powershell
   wsl --install
   ```
   Si el comando no está disponible, instale el rol **Contenedores** desde el Administrador del Servidor (Server Manager → Agregar roles y características → Contenedores) en su lugar.
2. Instale Docker Engine (no Desktop) siguiendo la guía oficial de Microsoft/Docker para Windows Server, o pida a TI que lo haga con el paquete `mirantis/docker` o `docker-ce` correspondiente a la versión del servidor.
3. Confirme igual que en Windows 10/11:
   ```powershell
   docker --version
   docker compose version
   ```

> (NOTE) En Windows Server, el firewall puede mostrar el perfil de red como **Dominio** en vez de **Privado** si el servidor está unido a un dominio de Active Directory — revise cuál perfil aplica antes de crear las reglas del Capítulo 7, y use ese perfil (nunca "Público" ni "Cualquiera").

### Linux (Ubuntu / Debian y similares)

1. Ejecute el script oficial de instalación:
   ```bash
   curl -fsSL https://get.docker.com | sh
   ```
2. Agregue su usuario al grupo `docker` para no tener que usar `sudo` en cada comando (cierre sesión y vuelva a entrar para que tome efecto):
   ```bash
   sudo usermod -aG docker $USER
   ```
3. Confirme que el plugin de Compose esté presente (si el paso siguiente falla, instálelo):
   ```bash
   sudo apt-get update && sudo apt-get install -y docker-compose-plugin
   ```
4. Confirme la instalación:
   ```bash
   docker --version
   docker compose version
   ```

> (WARN) Este manual siempre usa **`docker compose`** (dos palabras, con espacio) — el plugin moderno. Nunca use la herramienta antigua `docker-compose` (una palabra, con guión); si es la única que tiene instalada, instale el plugin nuevo en su lugar.

## 3. Qué hacer si Docker no está disponible

A veces Docker no se puede instalar de inmediato. Antes de rendirse, pruebe en este orden:

1. **La virtualización está deshabilitada en el BIOS/UEFI.** Docker en Windows necesita virtualización de hardware activada. Reinicie, entre al BIOS (usualmente `F2`, `Del` o `F10` al encender) y active **Intel VT-x** o **AMD-V** / "Virtualization Technology". Guarde y reinicie.
2. **Windows Home sin WSL 2.** Docker Desktop en Windows Home requiere WSL 2. Instálelo con:
   ```powershell
   wsl --install
   ```
   y reinicie cuando lo pida.
3. **La política de la empresa bloquea Docker Desktop** (licenciamiento corporativo, restricciones de TI). Use en su lugar una alternativa compatible con los mismos comandos:
   - **Docker Engine sin interfaz gráfica** (línea de comandos solamente) — funciona igual para todo este manual, ya que nunca se usa la interfaz de Docker Desktop, solo la terminal.
   - **Podman Desktop** — alternativa gratuita compatible con `docker compose`; los comandos de este manual funcionan igual reemplazando `docker` por `podman` si así lo indica su instalación.
4. **Sigue sin funcionar.** Escale a la persona encargada de TI o del servidor con esta información exacta: *"Necesito un motor de contenedores compatible con Docker Compose, con los puertos 443 y 80 libres en el servidor, y al menos 4 GB de espacio en disco."*

> (NOTE) Este capítulo no reemplaza a Docker por una instalación manual de Python, Node.js, PostgreSQL, Redis y un servidor web por separado — esa ruta existe en teoría, pero es un proyecto de infraestructura mucho más grande y no está cubierta por este manual. El objetivo aquí es conseguir que Docker (o un reemplazo compatible) funcione.

## 4. Comandos Docker esenciales (referencia rápida)

Todos se ejecutan desde la carpeta `infra/`. Para producción siempre se usan **ambos** archivos de configuración encadenados con `-f`.

| Comando | Qué hace | Cuándo usarlo |
|---|---|---|
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build` | Descarga, construye e inicia todo el sistema en segundo plano | Primera instalación, o después de recibir código nuevo |
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml ps` | Muestra el estado de cada pieza (contenedor) | Para confirmar que todo está corriendo |
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f [servicio]` | Muestra el registro de actividad en vivo | Para diagnosticar un problema |
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml down` | Detiene el sistema (los datos se conservan) | Para apagar el sistema de forma segura |
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend sh` | Abre una terminal dentro del backend | Solo para diagnóstico avanzado |
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate [servicio]` | Reinicia una sola pieza | Después de cambiar `.env` |

> (DANGER) El comando `down -v` (con `-v` al final) **borra permanentemente** la base de datos y todos los archivos subidos. Nunca lo ejecute en un servidor con datos reales, a menos que tenga un respaldo reciente y la intención deliberada de borrar todo. Vea el **Manual de Respaldo** antes de usar cualquier variante de `down` con `-v`.

## 5. Configuración del archivo `.env`

La aplicación lee sus contraseñas y ajustes desde un archivo llamado `.env` dentro de `infra/`. Este archivo nunca se comparte ni se sube a un repositorio — cada servidor tiene su propia copia con sus propios valores.

1. Copie la plantilla:
   - **Windows:** `copy .env.example .env`
   - **Linux:** `cp .env.example .env`
2. Abra `.env` con un editor de texto y complete estos valores (el resto puede quedar con su valor por defecto):

| Variable | Para qué sirve |
|---|---|
| `DJANGO_SECRET_KEY` | Clave criptográfica interna del backend. **Secreta.** |
| `POSTGRES_PASSWORD` | Contraseña de la base de datos. **Secreta.** |
| `REDIS_PASSWORD` | Contraseña de la caché (obligatoria en producción). **Secreta.** |
| `PII_FIELD_KEY` | Clave que cifra los datos personales de los pacientes en la base de datos. **Secreta — lea la advertencia abajo.** |
| `DJANGO_ALLOWED_HOSTS` | Direcciones que el backend acepta — agregue la IP del servidor (Capítulo 6). |
| `DJANGO_CORS_ALLOWED_ORIGINS` | Origen web autorizado a llamar la API — `https://<IP-del-servidor>`. |
| `TZ` | Zona horaria, use `America/Santo_Domingo`. |

Para generar los tres valores secretos, use estos comandos (funcionan igual en Windows y Linux si Docker ya está instalado, sin necesidad de tener Python instalado en el servidor):

```bash
docker run --rm python:3.13-alpine python -c "import secrets; print(secrets.token_urlsafe(64))"
docker run --rm python:3.13-alpine sh -c "pip install -q cryptography && python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
```

El primero sirve para `DJANGO_SECRET_KEY`; el segundo, para `PII_FIELD_KEY`. Para `POSTGRES_PASSWORD` y `REDIS_PASSWORD`, cualquier contraseña larga y aleatoria sirve — puede reutilizar una salida del primer comando.

> (DANGER) Una vez que el sistema tenga pacientes reales guardados, **`PII_FIELD_KEY` nunca debe cambiarse.** Cambiarla vuelve ilegible para siempre cada registro de paciente existente — no hay forma de recuperar esos datos después sin la clave original. Configúrela una sola vez, correctamente, antes de poner el sistema en uso real, y guarde una copia segura del archivo `.env` completo (vea el Manual de Respaldo). Si alguna vez es realmente necesario rotarla, eso requiere el comando especial `reencrypt_pii` — nunca editar el archivo directamente.

> (WARN) Nunca suba `.env` a un repositorio de código, lo envíe por correo, ni lo guarde fuera del servidor y un respaldo seguro. Contiene todas las contraseñas y claves de cifrado del sistema.

## 6. Encontrar la dirección IP del servidor

**Windows:**
```powershell
ipconfig
```
Busque `Dirección IPv4` bajo el adaptador de red activo (Wi-Fi o Ethernet), por ejemplo `192.168.1.42`.

**Linux:**
```bash
hostname -I
```
Busque una dirección que empiece con `192.168.`, `10.` o `172.16.`–`172.31.` — esos rangos son de red privada.

Vuelva a `.env` y complete las dos líneas con esa dirección:

```
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,backend,192.168.1.42
DJANGO_CORS_ALLOWED_ORIGINS=https://192.168.1.42
```

> (TIP) Pida a quien administre la red que **reserve** esa dirección IP para el servidor (una "reserva DHCP" o "IP estática"), para que no cambie después de un reinicio del router.

### Reservar la IP del servidor (evitar que cambie)

Por defecto, el router le asigna la IP al servidor de forma automática (DHCP), y **puede cambiarla** después de un reinicio del router o de un corte eléctrico. Si eso ocurre, `DJANGO_ALLOWED_HOSTS` y `DJANGO_CORS_ALLOWED_ORIGINS` quedan desactualizados y el sitio deja de cargar (vea "La IP del servidor cambió" en el Capítulo 11). Por eso, antes de continuar, reserve la IP con uno de estos dos métodos.

**Método 1 — Reserva DHCP en el módem/router (recomendado)**

1. Primero anote la **dirección MAC** del servidor (el identificador único de su tarjeta de red):
   - **Windows:**
     ```powershell
     ipconfig /all
     ```
     Busque `Dirección física` bajo el adaptador activo (Wi-Fi o Ethernet), con formato `XX-XX-XX-XX-XX-XX`.
   - **Linux:**
     ```bash
     ip link
     ```
     Busque `link/ether` bajo la interfaz activa, con formato `xx:xx:xx:xx:xx:xx`.
2. Entre al panel de administración del módem con la misma URL y credenciales del Capítulo 8 (`http://192.168.1.1` o `http://192.168.0.1`, usuario/contraseña en la etiqueta del equipo).
3. Busque la sección de **DHCP** — el nombre exacto varía por proveedor y modelo: "Reserva de IP", "Address Reservation", "Static DHCP Lease", "DHCP Binding". Si no la encuentra con ninguno de estos nombres, contacte al soporte técnico de Claro o Altice para que lo guíen en su equipo específico.
4. Ubique el servidor en la lista de dispositivos conectados por su dirección MAC (paso 1) y **reserve** la IP que ya tiene (la misma que anotó en la sección anterior). Guarde los cambios.

> (TIP) Esta es la opción preferida: la reserva vive en el router, así que no hay que tocar la configuración de red del servidor, y sigue funcionando aunque el servidor se reinstale o se reemplace la tarjeta de red (si se actualiza la MAC en el router).

**Método 2 — IP estática en el propio servidor**

Use este método solo si no tiene acceso al panel del router (por ejemplo, un router administrado por TI de forma centralizada). En ese caso, o pida a quien sí tenga acceso que aplique el Método 1, o configure la IP como manual/estática directamente en el servidor:

- **Windows:** Panel de Control → Redes → cambiar configuración del adaptador → clic derecho en el adaptador activo → Propiedades → `Protocolo de Internet versión 4 (TCP/IPv4)` → Propiedades → marque **"Usar la siguiente dirección IP"** y complete con la misma IP, máscara de subred y puerta de enlace que el adaptador ya tenía asignados por DHCP (visibles con `ipconfig /all` del paso 1).
- **Linux (NetworkManager, común en Ubuntu de escritorio):**
  ```bash
  nmcli con mod "<nombre-de-la-conexión>" ipv4.addresses 192.168.1.42/24 ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8 ipv4.method manual
  nmcli con up "<nombre-de-la-conexión>"
  ```
- **Linux (servidor con Netplan, común en Ubuntu Server):** edite el archivo en `/etc/netplan/` correspondiente, cambie `dhcp4: true` por una sección `addresses:`/`gateway4:` con la IP fija, y aplique con `sudo netplan apply`.

> (WARN) La IP que elija debe quedar **fuera** del rango que el router reparte por DHCP (revíselo en la misma sección de DHCP del panel del router), o puede chocar con la IP de otro dispositivo cuando el router se la asigne a alguien más.

Después de aplicar cualquiera de los dos métodos, confirme que la IP no cambió (`ipconfig` en Windows / `hostname -I` en Linux) y que coincide con la que ya tiene escrita en `.env`.

## 7. Primer despliegue

Desde la carpeta `infra/`:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Este único comando descarga y construye todo, genera un certificado HTTPS propio automáticamente, prepara la base de datos, y arranca las cinco piezas del sistema en segundo plano. La primera vez puede tardar varios minutos.

Verifique que todo esté corriendo:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

Debe ver cinco contenedores (`mc_prod_db`, `mc_prod_cache`, `mc_prod_backend`, `mc_prod_frontend`, `mc_prod_communications_worker`) en estado `running` o `healthy`.

> (NOTE) Si `mc_prod_frontend` falla en el primer arranque mencionando un certificado faltante, es una carrera de arranque conocida — el generador de certificados (`cert-init`) a veces termina un segundo después de que el sitio intenta leerlo. Vuelva a ejecutar el mismo comando `up -d` una vez más; es seguro repetirlo.

Cree la cuenta de administrador:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py create_admin --username admin --email admin@clinica.com --password "<contraseña-propia>"
```

> (WARN) Reemplace el usuario, el correo y especialmente la contraseña por valores propios — nunca deje la contraseña de ejemplo en un sistema real.

## 8. Capítulo de Red y Seguridad

Este es el capítulo más importante para proteger el sistema: **el objetivo es que la aplicación sea alcanzable solo dentro de la red de la clínica, y completamente invisible desde internet.**

### Firewall del servidor (Windows y Linux)

**Windows (10, 11 y Server — mismo comando en los tres):** abra PowerShell **como Administrador**:
```powershell
New-NetFirewallRule -DisplayName "MedicalConsultations HTTPS" `
  -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow -Profile Private
New-NetFirewallRule -DisplayName "MedicalConsultations HTTP" `
  -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow -Profile Private
```

**Linux (`ufw`, común en Ubuntu/Debian):**
```bash
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
```
Si su servidor usa `firewalld` en lugar de `ufw`:
```bash
sudo firewall-cmd --permanent --add-port=443/tcp --add-port=80/tcp && sudo firewall-cmd --reload
```

> (DANGER) El perfil del firewall debe ser siempre **Privado** (`-Profile Private`) — nunca "Público", "Dominio" (salvo que el servidor esté realmente unido a un dominio interno confiable) ni "Cualquiera". Un perfil equivocado aplicaría la misma regla en redes no confiables.

### El módem/router: Claro Dominicana y Altice Dominicana

La mayoría de los equipos que Claro Dominicana y Altice Dominicana entregan a sus clientes (residenciales o de negocio) son combinaciones de módem + router ("ONT-router") con un panel de administración web. Los pasos exactos varían según el modelo y la versión del equipo, pero el objetivo siempre es el mismo:

1. **Ingrese al panel de administración** del módem — normalmente en `http://192.168.1.1` o `http://192.168.0.1` desde un navegador conectado a esa red. El usuario y la contraseña por defecto suelen estar impresos en una etiqueta pegada al equipo. Si fueron cambiados y no los tiene, contacte al soporte técnico del proveedor (Claro o Altice).
2. **Deshabilite UPnP** (Universal Plug and Play) — esta función permite que programas dentro de la red abran puertos hacia internet automáticamente, sin avisar. Para este sistema no se necesita, y es un riesgo de seguridad dejarlo activo.
3. **Confirme que la DMZ esté deshabilitada** — la DMZ expone una computadora completa directamente a internet; nunca debe apuntar al servidor de este sistema.
4. **No reenvíe (port-forward) ningún puerto** hacia el servidor — en particular los puertos **80, 443, 8000, 5432 y 6379**. Este sistema no necesita ningún puerto abierto desde internet hacia el servidor bajo ningún escenario cubierto por este manual.
5. **Reserve una IP fija para el servidor** dentro de la red local, para que las reglas de firewall configuradas arriba no se rompan si la IP cambia — vea el procedimiento paso a paso en la sección **"Reservar la IP del servidor"** del Capítulo 6.

> (NOTE) Los planes residenciales de Claro y Altice suelen usar **CGNAT** (una capa de traducción de direcciones compartida entre varios clientes), lo que de por sí ya dificulta que alguien desde internet alcance su red doméstica directamente. Esto es una protección adicional útil, **no un sustituto** de configurar bien el equipo — no dependa de ella únicamente.

> (WARN) Los nombres exactos de los menús varían según el modelo y la versión de firmware del módem entregado por cada proveedor. Si no encuentra alguna de estas opciones con ese nombre exacto, busque un término equivalente ("Port Forwarding", "Virtual Server", "Servidor Virtual", "NAT") o contacte al soporte técnico de Claro o Altice para confirmar cómo verificar que estas funciones estén apagadas en su equipo específico.

### Si se necesita acceso remoto legítimo

Si algún médico o administrador necesita entrar al sistema desde fuera de la clínica (otra sede, su casa), la forma correcta es una **VPN** (por ejemplo WireGuard, o un servicio de VPN empresarial que ofrezca el proveedor de internet) — nunca abrir puertos directamente en el router. Una VPN hace que el dispositivo remoto se comporte como si estuviera físicamente dentro de la red de la clínica, sin exponer el servidor a internet en ningún momento. Configurar una VPN es trabajo de un técnico de red y está fuera del alcance de este manual.

## 9. Operación día a día

```bash
# Detener el sistema (los datos se conservan)
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# Iniciarlo de nuevo
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Ver el estado
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps

# Ver el registro de actividad
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f [servicio]
```

Después de recibir código nuevo del equipo de desarrollo, reconstruya y reinicie:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

> (NOTE) Los cambios en ajustes del día a día (reglas de bloqueo de sesión, duración de sesiones, tamaño máximo de archivos, etc.) normalmente **no** requieren tocar Docker — un administrador puede cambiarlos directamente desde la página de Configuración dentro del sistema.

## 10. Respaldos

El respaldo y la restauración de datos tienen su propio documento completo: consulte el **Manual de Respaldo** (`manual-respaldo.html`). No se repite aquí para evitar que ambos documentos queden desactualizados entre sí.

## 11. Solución de problemas

**Un puerto ya está en uso / el sistema no arranca.**
- Windows: `Get-NetTCPConnection -LocalPort 443`
- Linux: `sudo ss -tulpn | grep :443`

Es probable que otro programa esté usando ese puerto. Deténgalo, o cambie el puerto que usa este sistema (consulte a su desarrollador).

**Un contenedor se reinicia solo o aparece como "unhealthy".**
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f <nombre-del-servicio>
```
Lea las últimas líneas del registro. La causa más común en el primer arranque es la carrera del certificado descrita en el Capítulo 7 — vuelva a ejecutar `up -d`.

**El navegador muestra una advertencia de certificado.**
Es esperado — vea el Capítulo 7. No es una señal de problema.

**Se olvidó la contraseña de administrador.**
Cree una nueva cuenta de administrador con el mismo comando del Capítulo 7 usando otro nombre de usuario, o pida a su desarrollador que restablezca la contraseña de la cuenta existente.

**Cambió `PII_FIELD_KEY` por accidente y ahora no puede leer los datos de pacientes.**
No entre en pánico ni reinicie el sistema repetidamente. Ponga de vuelta la clave **anterior** en `.env` de inmediato para que el sistema pueda volver a leer los datos existentes, y luego pida a su desarrollador que ejecute la rotación correcta de la clave:
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec backend python manage.py reencrypt_pii --old-key <CLAVE_ANTERIOR>
```

**La IP del servidor cambió y ya nada carga.**
Actualice `DJANGO_ALLOWED_HOSTS` y `DJANGO_CORS_ALLOWED_ORIGINS` en `.env` con la nueva dirección (Capítulo 6), luego:
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate backend frontend
```

## 12. Anexo — referencia completa de `.env`

| Variable | ¿Secreta? | Propósito |
|---|---|---|
| `DJANGO_SECRET_KEY` | Sí | Clave criptográfica del backend. |
| `DJANGO_DEBUG` | — | Debe quedar en `false` en producción — la configuración de producción ya lo fuerza. |
| `DJANGO_ALLOWED_HOSTS` | — | Direcciones/IPs que el backend acepta. |
| `DJANGO_CORS_ALLOWED_ORIGINS` | — | Orígenes autorizados a llamar la API. |
| `TZ` | — | Zona horaria del servidor. |
| `POSTGRES_DB` / `POSTGRES_USER` | — | Nombre y usuario de la base de datos. |
| `POSTGRES_PASSWORD` | Sí | Contraseña de la base de datos. |
| `REDIS_PASSWORD` | Sí | Contraseña de la caché, obligatoria en producción. |
| `JWT_ACCESS_LIFETIME_MINUTES` | — | Duración de la sesión de acceso. |
| `JWT_REFRESH_LIFETIME_DAYS` | — | Días antes de tener que iniciar sesión de nuevo. |
| `PII_FIELD_KEY` | Sí | Cifra los datos personales de los pacientes. **Nunca cambiar con datos reales ya guardados.** |
| `EMAIL_HOST` / `EMAIL_PORT` / `EMAIL_HOST_USER` / `EMAIL_USE_TLS` / `DEFAULT_FROM_EMAIL` | — | Correo del módulo Comunicaciones (opcional). |
| `EMAIL_HOST_PASSWORD` | Sí | Contraseña del correo anterior. |

**Dónde queda todo una vez desplegado:**

| Qué | Dirección |
|---|---|
| El sitio web | `https://<IP-del-servidor>` |
| Verificación de salud de la API | `https://<IP-del-servidor>/api/health/` |

El panel de administración de Django (`/admin/`) y la documentación de la API (`/api/docs/`) existen pero están restringidos a cuentas Admin/IT — el uso diario solo necesita la dirección principal del sitio.
