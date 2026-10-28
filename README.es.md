<p align="center">
  <a href="README.md">English</a> · <b>Español</b>
</p>

<p align="center">
  <img src="icons/syncing.png" width="96" alt="SyncDood sincronizando">
  <img src="icons/ok.png" width="96" alt="SyncDood al día">
  <img src="icons/error.png" width="96" alt="SyncDood con error">
</p>

# SyncDood — sincroniza tus saves y states entre PCs

> **Versión 0.1** · Se adapta al idioma de Windows (español / inglés).

Mantiene tus carpetas de partidas guardadas (saves) y estados (states) iguales en todas tus PCs usando tu nube, con un ícono en la bandeja del sistema y una ventana para ver el historial y cambiar carpetas, nube y opciones **sin tocar ningún archivo**. Pensado para RetroArch, pero sirve para cualquier carpeta.

**Piezas:** [rclone](https://rclone.org) (hace la sync bidireccional con `bisync`) + un script de AutoHotkey v2 (ícono, timers, detección de suspensión e historial).
**Recursos:** el script en reposo usa unos pocos MB y casi 0% de CPU. `rclone` solo se abre durante la sincronización y se cierra solo.

## Instalación

Haz esto **en cada PC** que quieras sincronizar. No necesita permisos de administrador.

1. Descomprime la carpeta `SyncDood` donde quieras.
2. Doble clic a **`Install.bat`**. Descarga rclone y AutoHotkey v2 (versión portátil, dentro de la misma carpeta) y abre la app.
3. El asistente te pide, en orden:
   - la carpeta de **SAVES**,
   - la carpeta de **STATES**,
   - *(opcional)* otras carpetas que quieras agregar (por ejemplo, de otro emulador),
   - tu **nube**. Eliges de una lista y el asistente muestra **solo lo que esa nube necesita**; en las más fáciles basta con iniciar sesión en el navegador una vez.

   Al elegir carpetas se abre el selector normal de Windows: puedes **escribir o pegar la ruta** en la barra de direcciones de arriba.
4. Listo: configura el inicio con Windows y hace la primera sincronización sola.

Las carpetas pueden estar en rutas distintas en cada PC; lo que debe coincidir entre PCs es la **nube** y el **nombre** de cada carpeta (`saves`, `states`, o el que hayas puesto a las extra).

### Primera sincronización

Se fusiona esta PC con la nube: lo que solo exista en un lado se copia al otro, y si un archivo existe en ambos gana el **más reciente**. Lo que pierda se guarda en la carpeta de respaldos, así que no se pierde nada. Puedes instalar en las PCs en cualquier orden.

Si prefieres que en una PC siempre gane un lado, cámbialo en la ventana de SyncDood → sección **Opciones** → *Primera sincronización: quién gana*: el más reciente (por defecto), esta PC o la nube.

## ¿Vienes de RSY o SaveSync?

SyncDood es el nuevo nombre de RSY (y, antes, de SaveSync). Al abrir SyncDood por primera vez, si encuentra la configuración vieja (`%LOCALAPPDATA%\RSY` o `%LOCALAPPDATA%\SaveSync`) la mueve a `%LOCALAPPDATA%\SyncDood` y conserva tu nube y carpetas tal cual, sin volver a configurar nada. El acceso directo de inicio con Windows se recrea solo. Después puedes borrar la carpeta vieja y el `RSY.exe` / `SaveSync.exe` viejos.

## ¿Qué nube elegir?

Las marcadas con ★ son las más fáciles. Los espacios gratis son aproximados y los proveedores los cambian de vez en cuando.

| Nube | Qué te pide | Notas |
|---|---|---|
| ★ **OneDrive** | Solo iniciar sesión | ~5 GB gratis; viene con Windows. En cuentas de trabajo o escuela, si el navegador dice **"se necesita aprobación del administrador"**, tu organización bloquea apps externas: usa otra nube. |
| **Dropbox** | Solo iniciar sesión | ~2 GB gratis. |
| ★ **Carpeta de tu app de nube** | Elegir una carpeta | La forma fácil de usar **MEGA** (20 GB gratis, el que más da), **Google Drive** (15 GB, compartidos con Gmail y Fotos), iCloud y similares, con su app de escritorio: sin cuentas ni credenciales. Ver abajo. |
| Filen *(avanzado)* | Correo, contraseña y API key | 10 GB gratis, cifrado de extremo a extremo. Conexión directa, sin ninguna app extra abierta. Requiere rclone 1.73 o más nuevo. Ver abajo. |
| **Carpeta de red, NAS o servidor propio** | Elegir una carpeta (ruta de red como `\\MiNAS\saves` o unidad como `Z:\saves`) | Sin cuentas ni claves; solo necesitas poder abrir la carpeta desde Windows. Úsala si montas tu propio NAS o servidor. Ver abajo. |
| **pCloud** | Solo iniciar sesión | Empiezas con ~5 GB; llegar a ~10 GB exige completar tareas o invitar gente. |
| **Box** | Solo iniciar sesión | ~10 GB gratis; máximo 250 MB por archivo en el plan gratis. |
| Google Drive directo *(avanzado)* | ID y secreto de cliente propios | Google retira el acceso simple de rclone durante 2026; ver abajo. |
| Backblaze B2 *(avanzado)* | keyID, applicationKey y nombre del bucket | Pensado para usuarios técnicos. |
| Nextcloud / ownCloud *(avanzado)* | Dirección del servidor, usuario y contraseña de aplicación | Para tu propio servidor o un NAS compatible. |
| Otra *(avanzado)* | El asistente manual de rclone | rclone soporta decenas de nubes. Crea un remote llamado `syncdood`. |

Todas deben guardar la fecha de modificación de los archivos (la regla "gana el más reciente" depende de eso). MEGA conectado directo a rclone, por ejemplo, no la soporta bien; si usas MEGA, hazlo con su app de escritorio y la opción *Carpeta de tu app de nube*.

### Carpeta de tu app de nube (recomendada para MEGA y Google Drive)

Si ya usas la app de escritorio de tu nube, no hace falta conectar nada más:

1. Instala la app (por ejemplo, *MEGA* o *Google Drive para escritorio*) e inicia sesión.
2. En SyncDood elige **Carpeta de tu app de nube** y selecciona una carpeta dentro de ella. SyncDood creará ahí una subcarpeta `SyncDood`.
3. Repite en cada PC con la **misma cuenta**.

SyncDood sincroniza tus saves con esa carpeta y la app de la nube se encarga de subirla a internet. Dos cosas a cuidar: la app de la nube tiene que estar abierta, y la carpeta debe estar disponible sin conexión (en Google Drive, modo *Reflejar archivos*; en OneDrive, *Mantener siempre en este dispositivo*). Los cambios tardan un poco más en llegar a las otras PCs, porque dependen de dos sincronizaciones seguidas.

### Carpeta de red, NAS o servidor propio

Sirve para guardar tus saves en tu propio NAS, otro PC o un servidor, sin depender de ninguna nube:

1. Comparte una carpeta en el NAS o servidor (SMB/Samba, lo normal en Windows, Synology, QNAP, TrueNAS, Linux con Samba…).
2. Comprueba que puedes abrirla desde el Explorador de Windows (`\\MiNAS\saves`) o asígnale una letra de unidad.
3. En SyncDood elige **Carpeta de red, NAS o servidor propio** y selecciona esa carpeta (o pega la ruta en la barra de direcciones). SyncDood creará dentro una subcarpeta `SyncDood`.
4. Repite en cada PC apuntando a la **misma carpeta compartida**.

Si el NAS está apagado o fuera de tu red, la sync falla y se reintenta en la siguiente ronda, sin perder nada. Si más adelante quieres llegar a tu servidor desde fuera de casa, tienes dos caminos: una VPN hacia tu red (y sigues usando esta opción) o instalar Nextcloud y usar la opción *Nextcloud / ownCloud*.

### Filen directo (avanzado)

SyncDood se conecta a Filen mediante rclone, sin ninguna app de escritorio. rclone necesita tres datos: el correo de tu cuenta, tu contraseña y una **API key**. Filen solo entrega la API key con su herramienta de línea de comandos, así que lo haces una vez por cuenta:

1. Descarga la [CLI de Filen](https://docs.cli.filen.io/) (un programa pequeño; no tiene que quedarse instalado).
2. Inicia sesión con ella y ejecuta el comando `export-api-key`. Copia la clave.
3. En SyncDood elige **Filen (avanzado)** y pega correo, contraseña y API key. Repite en cada PC con la misma cuenta.

Notas: requiere **rclone 1.73 o más nuevo**; `Install.bat` y `Build.bat` descargan el rclone actual, pero si tenías un `rclone.exe` viejo junto al script, reemplázalo. Si cambias tu contraseña de Filen debes exportar la API key de nuevo y volver a ingresar los tres datos en la ventana de SyncDood → *Nube*.

### Google Drive directo (avanzado)

Google va a cobrar por la app compartida de rclone y la está retirando durante 2026, así que conectar directo exige credenciales propias:

1. En [console.cloud.google.com](https://console.cloud.google.com) crea un proyecto.
2. Activa la **Google Drive API**.
3. *Pantalla de consentimiento OAuth*: tipo **Externo**, agrega tu correo como usuario de prueba y **publica la app ("En producción")**. Si la dejas en "Prueba", el acceso caduca a los 7 días.
4. *Credenciales → Crear credenciales → ID de cliente de OAuth* → **Aplicación de escritorio**.
5. Pega el *ID de cliente* y el *secreto* en el asistente.

Google puede avisar "app no verificada": es tu propia app, continúa. Si todo esto te suena a mucho, usa mejor *Carpeta de tu app de nube*.

## Crear un solo `SyncDood.exe`

Si prefieres repartir **un único archivo** (sin Install.bat, sin instalar AutoHotkey, sin descargas en la PC de destino):

1. En una PC con Windows, abre esta carpeta y haz doble clic a **`Build.bat`**.
2. La primera vez descarga rclone, AutoHotkey v2 y Ahk2Exe (se guardan en `build\cache`, así que después es instantáneo) y compila.
3. Queda en **`dist\SyncDood.exe`**. Cópialo a cualquier PC y ábrelo: aparece el asistente de siempre.

Qué lleva adentro: el runtime de AutoHotkey, el script, `rclone.exe` y los íconos. Al abrirlo desempaqueta rclone y los íconos en `%LOCALAPPDATA%\SyncDood\bin` (solo cuando el .exe cambia de versión). La configuración sigue en `%LOCALAPPDATA%\SyncDood\`.

Cosas a tener en cuenta:

- Pesa unos 60 MB, casi todo es rclone.
- Deja el `.exe` en una carpeta fija (por ejemplo `C:\Programas\SyncDood`): el inicio con Windows apunta a donde esté. Si lo mueves, desmarca y vuelve a marcar *Iniciar con Windows* en el menú del ícono.
- Para actualizar rclone o cambiar el script, borra `build\cache\rclone.exe` (si quieres bajar el rclone más nuevo) y vuelve a correr `Build.bat`.
- El `.exe` no está firmado digitalmente: Windows SmartScreen puede avisar la primera vez («Más información → Ejecutar de todos modos»), y algunos antivirus marcan por error los ejecutables hechos con AutoHotkey. Si pasa, agrega una excepción o compílalo tú mismo en esa PC con `Build.bat`.
- Si la red bloquea las descargas, pon `rclone.exe`, `AutoHotkey64.exe` (v2) y `Ahk2Exe.exe` en `build\cache` y vuelve a ejecutar.

## Íconos

El logo es una **R** que cambia de color según el estado de la sincronización:

| Ícono | Significado |
|---|---|
| Azul | Sincronizando |
| Verde | Todo sincronizado (el tooltip muestra la hora y cuántos archivos subió ↑ y bajó ↓) |
| Rojo | Falló la sync (el tooltip dice cuál) |
| Rojo ↔ ámbar (parpadea) | Hubo un conflicto que aún no revisas; deja de parpadear al abrir la ventana |

**Doble clic al ícono = abre la ventana de SyncDood.** Clic derecho abre el menú: *Abrir SyncDood*, *Sincronizar ahora*, abrir carpetas/log, *Buscar actualizaciones*, *Acerca de / Créditos*, *Apoyar en Patreon*, *Proyecto en GitHub*, *Iniciar con Windows* y *Salir*.

## La ventana de SyncDood

Barra lateral con siete secciones. Todo se configura aquí, sin editar `config.ini`. Los cambios de carpetas, nube y opciones reinician SyncDood solos y vuelven a abrir la ventana. El tema (claro / oscuro) sigue al de Windows, o lo eliges en *Opciones → Apariencia*.

- **Estado:** el color del encabezado resume todo (azul sincronizando, verde al día, ámbar conflicto, rojo error), con la última sincronización, la próxima revisión, una barra mientras trabaja, el estado de cada carpeta (con su propio botón *Sincronizar*) y la actividad reciente.
- **Historial:** los últimos 200 eventos por carpeta, con filtro por carpeta y colores: ↑ Subido (verde) · ↓ Descargado (verde azulado) · ✕ Borrado (gris) · ⚠ Conflicto (ámbar) · ✖ Falló (rojo).
- **Partidas:** una tarjeta por juego (captura, emulador y número de states); busca por nombre o emulador y ordena A–Z o por más reciente. Doble clic en un juego para ver sus slots (captura, fecha, origen y tamaño de cada state). Reconoce los states de **RetroArch** (`.state`, `.state1`… `.state.auto` + el `.png` junto a cada uno), **DuckStation** (`SLUS-00594_1.sav`, en una carpeta `savestates`), **PCSX2** (`.p2s`), **Dolphin** (`.s01`–`.s10`), **Azahar** (`.cst`) y **PPSSPP** (`.ppst` + su `.jpg`); agrega la carpeta de states de cada emulador en *Carpetas* como cualquier otra. Los emuladores que guardan el juego como ID (serial / title ID) muestran ese ID; para ver nombres reales abre el juego y pulsa **Renombrar juego…** (se guarda en `%LOCALAPPDATA%\SyncDood\gamenames.ini`, una línea `ID=Nombre`, p. ej. `SLUS-00594=Final Fantasy VII`; también puedes editar ese archivo a mano). **Buscar nombres** busca los nombres reales de los juegos que aún muestran un ID (DuckStation con la lista de libretro/Redump, Dolphin con GameTDB; se descarga solo al pulsarlo; tus nombres siempre ganan; los IDs de Azahar y PPSSPP solo se pueden renombrar a mano). **Depurar versiones…** borra las versiones viejas de partidas tanto en esta PC como en la nube, avisando antes cuántas son. El origen es el **nombre de la PC** que lo subió (se cambia en *Opciones → Nombre de esta PC*; por defecto es el nombre del equipo en Windows). Selecciona un slot (o doble clic) → **Versiones anteriores / Restaurar…**: muestra las copias que SyncDood **ya guarda** en los respaldos (las de esta PC, y con *Incluir respaldos de la nube* también las de la nube), cada una con su captura. **Restaurar** copia primero el state actual a los respaldos (así puedes deshacer), pone la versión elegida como la más reciente y se sincroniza a tus otras PCs en la próxima sync. Lo único extra que se guarda es una lista de texto pequeña, por PC, de qué states subió (en la nube, en `_pcs/`, fuera de tus carpetas sincronizadas); así se sabe el nombre del origen.
  - **Emuladores sin states de archivo** (SyncDood no los muestra en Partidas, pero sus *partidas guardadas normales* sí se sincronizan agregando su carpeta en *Carpetas*): **Ryujinx/Ryubing** y **Cemu** no tienen save states; **RPCS3** y **Vita3K** tampoco (solo guardados del juego); **TeknoParrot** depende de cada juego y no tiene states; **Xemu** guarda snapshots dentro del disco virtual `.qcow2`, no como archivos sueltos, así que no se pueden listar por slot.
- **Carpetas vacías:** se sincronizan como carpetas reales en las nubes que las tienen (OneDrive, Dropbox, pCloud, Nextcloud, carpeta/NAS…). **Backblaze B2** no tiene carpetas reales, así que ahí las vacías se ignoran (ni se crean ni se borran en ningún lado); los emuladores recrean las que necesitan.
- **Carpetas:** agrega otras carpetas, cambia la ruta local, quítalas, ábrelas, **sincroniza solo la carpeta seleccionada**, edita sus **exclusiones** o lanza *Primera sincronización / reparar*. El nombre de cada carpeta es la subcarpeta en la nube y debe ser el mismo en todas tus PCs; la ruta local puede cambiar.
- **Nube:** muestra la nube actual, permite **cambiarla** y **probar la conexión**.
- **Opciones:** idioma, apariencia, intervalo, proceso del emulador, espera tras suspensión, espera de archivos en escritura, quién gana en la primera sync, respaldos, iniciar con Windows, actualizaciones y modo prueba.
- **Acerca de:** versión, créditos y *Buscar actualizaciones*.

> El historial sale del propio registro de rclone (qué archivos cambiaron en esta PC y cuáles en la nube), así que muestra lo que rclone realmente decidió. Una ↓ significa que **la nube tenía una versión distinta** (normalmente porque otra PC la guardó); si no cuadra, revisa el historial de la otra PC.

### Exclusiones

En *Carpetas → Exclusiones…* escribes reglas, una por línea (sintaxis de rclone, sin importar mayúsculas):

| Regla | Excluye |
|---|---|
| `*.log` | archivos por nombre, en cualquier subcarpeta |
| `shaders/` | cualquier carpeta llamada `shaders` y su contenido |
| `/logs/` | solo la carpeta `logs` de la raíz |
| `/xbox_hdd.qcow2` | un archivo concreto en la raíz |

Hay botones para elegir un archivo o carpeta y sugerencias comunes (`*.log`, `shaders/`, `cache/`, `*.qcow2`), y una vista previa te dice cuántos archivos y cuánto espacio dejarías de sincronizar. Las reglas pueden nombrar **carpetas enteras** (`shaders/`, `/colecciones/`) además de archivos. Si editas las reglas, la siguiente sync vuelve a listar esa carpeta sola (combina, **gana el más reciente**, no se borra nada). Lo excluido se ignora **en ambos lados y nunca se borra**: lo que ya estaba en la nube se queda ahí (bórralo a mano si quieres liberar espacio). Las reglas viven en `%LOCALAPPDATA%\SyncDood\exclude\<carpeta>.txt` y son por PC.

## Actualizaciones

SyncDood consulta las *Releases* de GitHub (`kyaaadood/SyncDood`) en segundo plano, como máximo una vez al día y sin avisar si no hay nada nuevo. También puedes pulsar *Buscar actualizaciones* en el menú del ícono o en *Acerca de*. Si hay una versión más nueva, te ofrece abrir la página de descarga. Se puede apagar en *Opciones*.

### Publicar una versión nueva

El número de versión vive en **un solo lugar**: la línea `AppVersion` al inicio de `SyncDood.ahk` (ahora `AppVersion := "0.1"`). Para sacar una versión nueva:

1. Cambia `AppVersion` (por ejemplo a `"0.2"` para la siguiente versión).
2. Crea una *Release* en GitHub en `kyaaadood/SyncDood` con la misma etiqueta precedida de `v` (`v0.2`).
3. Las copias instaladas comparan esa etiqueta con su `AppVersion` y ofrecen la página de descarga si es más nueva.

`Build.bat` también lee `AppVersion` y la escribe en las propiedades de `SyncDood.exe`, así que no hace falta tocar a mano la línea `;@Ahk2Exe-SetVersion`.

## Cuándo sincroniza

- 15 s después de iniciar el script.
- Cada `intervalMin` minutos (5 por defecto).
- ~20 s después de **reanudar de suspensión** (da tiempo a que vuelva el WiFi).
- ~3 s después de que **cierras el emulador** (`watchProcess`, `retroarch.exe` por defecto) para subir el último save/state.
- Manual: menú → *Sincronizar ahora*.
- Sincroniza **aunque el emulador esté abierto**.

Si falla (por ejemplo, sin internet tras despertar), reintenta 2 veces con 45 s de separación antes de avisar; después sigue intentando en el timer normal.

## Conflictos y respaldos

Un conflicto ocurre si el mismo archivo cambió en **ambas PCs** desde la última sync.

1. Gana la versión **más reciente** (queda con su nombre normal en las dos PCs).
2. La versión perdedora **se mueve a la carpeta de respaldos**, no se pierde: `<backupDir>\<carpeta>\conflicts\<fecha_hora>\...`
3. El ícono parpadea entre rojo y ámbar (no hay avisos emergentes) y queda el evento ⚠ en el Historial. Al abrir la ventana de SyncDood se considera revisado.

Además, todo lo que la sync **borre o sobrescriba** se respalda por día, en la PC (`<backupDir>\<carpeta>\<yyyy-MM-dd>\`) y en la nube (`_backup/<carpeta>/<yyyy-MM-dd>/`).

Los respaldos locales se limpian solos pasados `backupKeepDays` (30 por defecto), al iniciar SyncDood y cada hora mientras sincroniza. Los de la nube no se borran solos; límpialos a mano de vez en cuando. La limpieza automática borra respaldos y copias de conflictos pasados `backupKeepDays`, pero **nunca borra versiones de partidas** (`.state`, `.state1`, `.state.auto` y sus capturas): esas se quedan en *Versiones anteriores* hasta que las quites con **Partidas → Depurar versiones…** (tú eliges cuántos días conservar).

> Los respaldos solo se crean cuando una **sync reemplaza o borra** un archivo, no cada vez que guardas en el emulador, y se guardan **por día**: si un mismo archivo se reemplaza varias veces el mismo día, queda la copia más reciente de ese día.

Para recuperar algo: sección *Opciones* → *Abrir respaldos* (o el menú del ícono → *Abrir carpeta de respaldos*) y copia el archivo a su lugar.

## Configuración (`config.ini`)

Normalmente **no necesitas tocarlo**: todo se cambia desde la ventana de SyncDood. Vive en `%LOCALAPPDATA%\SyncDood\` junto con `sync.log` y la carpeta `data\` (botón *Abrir config.ini* en *Opciones*; después de editarlo a mano, Salir y volver a abrir SyncDood).

| Clave | Qué hace | Por defecto |
|---|---|---|
| `language` | `auto` (idioma de Windows), `en` o `es` | `auto` |
| `firstSyncWins` | Quién gana en la primera sync: `newer`, `local`, `cloud` | `newer` |
| `intervalMin` | Minutos entre revisiones | `5` |
| `watchProcess` | Proceso del emulador; al cerrarse se sincroniza (vacío = desactivado) | `retroarch.exe` |
| `resumeDelaySec` | Segundos de espera tras reanudar de suspensión | `20` |
| `pcName` | Nombre de esta PC, se muestra como origen de tus states (vacío = nombre del equipo en Windows) | *(vacío)* |
| `parallelOverride` | Archivos que se transfieren a la vez (1-32; las comprobaciones van al doble). `0` = automático: 8 para Backblaze B2, Nextcloud, carpeta y NAS, 4 para el resto (más puede hacer que Google Drive, OneDrive o Dropbox te limiten). Se cambia en Opciones (Auto / Manual); al cambiar de nube vuelve a automático | `0` |
| `maxDeletePct` | Protección contra borrados: una sync que borraría más de este % de los archivos de una carpeta se detiene antes de tocar nada. Con *Sincronizar ahora* te muestra qué se borraría (en esta PC / en la nube) y te pregunta si continuar; las automáticas solo dejan esa carpeta detenida. `0` = apagada. Se cambia en Opciones | `25` |
| `pruneCloudBackups` | `1` limpia también los respaldos y conflictos viejos de la nube (`_backup/`), con los mismos días de `backupKeepDays`, como máximo una vez al día. Las versiones de states se quedan y tus carpetas sincronizadas nunca se tocan. En Backblaze B2 borra de verdad en lugar de ocultar el archivo (así libera espacio). Se cambia en Opciones | `0` |
| `backupDir` | Carpeta local de respaldos (fuera de las carpetas sincronizadas) | `%LOCALAPPDATA%\SyncDood\backups` |
| `backupKeepDays` | Días que se conservan los respaldos locales (`0` = siempre) | `30` |
| `checkUpdates` | `1` = buscar actualizaciones al iniciar | `1` |
| `dryRun` | `1` = modo prueba, solo escribe en `sync.log` lo que haría | `0` |
| `settleSec` | Segundos que debe llevar quieto un archivo antes de sincronizar (espera hasta ~45 s; `0` = no esperar) | `10` |
| `theme` | `auto` (sigue a Windows), `light` o `dark` | `auto` |
| `pauseWhileRunning` | `1` = no sincroniza solo mientras el emulador vigilado está abierto (sincroniza al cerrarlo) | `1` |

## Desinstalar y limpiar

Ventana de SyncDood → **Opciones**:

- **Desinstalar SyncDood…** quita el acceso directo de inicio, `%LOCALAPPDATA%\SyncDood` (ajustes, historial, log), la conexión de rclone a tu nube (las credenciales guardadas en este PC), los registros de sincronización de rclone para SyncDood y cualquier resto de SaveSync. Pregunta aparte si quieres borrar los respaldos locales y el propio programa (con scripts sueltos solo se borran los archivos propios de SyncDood, nunca toda la carpeta; con una carpeta de respaldos personalizada solo se borran las subcarpetas de SyncDood). **Nunca toca tu nube** (archivos ni su carpeta `SyncDood`) **ni tus carpetas de saves/states.**
- **Limpiar SaveSync viejo** borra solo lo que dejó el SaveSync anterior: `%LOCALAPPDATA%\SaveSync`, su acceso directo de inicio, la conexión de rclone `savesync` y sus registros de sincronización. Si SyncDood aún usa la conexión `savesync`, la conserva.

El `SaveSync.exe` viejo (donde lo hayas puesto) y la carpeta `SaveSync` dentro de tu nube no se borran solos; quítalos a mano si ya no los necesitas.

## Solución de problemas

- **Install.bat se cierra o dice que no puede ejecutar scripts:** la política del equipo puede bloquear PowerShell. Pon `rclone.exe` junto a `SyncDood.ahk`, instala [AutoHotkey v2](https://www.autohotkey.com/) y abre `SyncDood.ahk` directamente.
- **Las descargas están bloqueadas:** baja `rclone.exe` de [rclone.org/downloads](https://rclone.org/downloads/) y ponlo junto a `SyncDood.ahk`; instala AutoHotkey v2 aparte.
- **Ícono rojo y dice que requiere "Primera sincronización / reparar":** pasa si una sync se interrumpió en un mal momento o se movió/borró algo a mano en las carpetas. Menú → *Primera sincronización / reparar…*.
- **La cabecera muestra un error pero el texto se corta:** pulsa **Detalles** (arriba a la derecha de la ventana) para ver el mensaje completo y las últimas líneas de error de `sync.log`. El color del encabezado sigue al del ícono: verde = sincronizado, azul = sincronizando, ámbar = conflicto, rojo = error.
- **«cannot find prior Path1 or Path2 listings» en el log:** rclone no tiene registro de sincronización de esa carpeta y esa nube (por ejemplo tras migrar desde SaveSync o cambiar el nombre de la nube). SyncDood ahora lo detecta y hace una primera sincronización por su cuenta, que combina ambos lados y no borra nada.
- **Conflictos en una state/save mientras juegas (`.syncconflict1`):** el emulador reescribe ese archivo mientras rclone lo sube, y ambos lados parecen «cambiados». No se pierde nada: se queda tu copia (la más nueva) y la otra va a *respaldos → conflictos*. Para evitarlo, SyncDood **no sincroniza solo** mientras `watchProcess` (RetroArch por defecto) está abierto y sincroniza justo al cerrarlo (*Opciones → «No sincronizar automáticamente mientras el emulador está abierto»*). Puedes pulsar *Sincronizar ahora* cuando quieras.
- **Ver el log:** menú del ícono → *Abrir log* (`sync.log`, conserva solo los últimos 2 días).
- **Borrar un save a mano** se propaga a las otras PCs en la siguiente sync (así funciona una sync bidireccional), pero queda respaldado. Si borras más del 50% de los archivos de golpe, rclone se niega a sincronizar como protección.

## Notas

- Las PCs deberían tener la hora bien sincronizada (la regla de "gana el más reciente" depende de las fechas de los archivos).
- Los states pesan más que los saves; considera el espacio de tu nube (y el de los respaldos).
- Evita que dos PCs jueguen el mismo juego a la vez: la sync detecta el conflicto, pero una de las dos sesiones quedará solo como respaldo.
- `rclone bisync` está marcado como *beta* por el proyecto rclone. Con carpetas chicas funciona bien, pero conviene que mantengas alguna copia aparte de tus saves de vez en cuando.
- Los textos de la app siguen el idioma de Windows: español si Windows está en español, inglés en cualquier otro caso (se puede forzar en *Opciones*).

## 💛 Créditos

Hecho por **KyaaaDood** con Claude AI. 🤖✨

Sigue mi trabajo en [GitHub](https://github.com/kyaaadood) y, si quieres apoyar el proyecto, puedes hacerlo en [Patreon](https://www.patreon.com/cw/KyaaaDood).

SyncDood usa [rclone](https://rclone.org) (licencia MIT) y [AutoHotkey v2](https://www.autohotkey.com) (GPLv2); ver [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Regenerar los íconos

```
python tools/make_icons.py
```

Requiere [Pillow](https://python-pillow.org). Genera `icons/ok.ico`, `syncing.ico`, `error.ico` y `conflict.ico` (y los `.png` del README).
