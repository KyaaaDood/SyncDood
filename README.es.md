<p align="center">
  <a href="README.md">English</a> · <b>Español</b>
</p>

<p align="center">
  <img src="icons/syncing.png" width="96" alt="SyncDood sincronizando">
  <img src="icons/ok.png" width="96" alt="SyncDood al día">
  <img src="icons/error.png" width="96" alt="SyncDood con error">
</p>

# 🎮 SyncDood — tus partidas y states, iguales en todas tus PCs

> **Versión 0.2** · 🌍 Se adapta al idioma de Windows (español / inglés)

SyncDood mantiene tus **partidas guardadas** 💾 y tus **estados (states)** 📸 iguales en todas tus PCs usando **tu propia nube** ☁️. Vive en la bandeja del sistema y su ventana te deja ver el historial y cambiar carpetas, nube y opciones **sin editar ningún archivo**. Pensado para RetroArch, pero funciona con cualquier carpeta.

🪶 Ligero: en reposo usa unos pocos MB y casi 0% de CPU. `rclone` solo corre mientras sincroniza.
🧩 Hecho con [rclone](https://rclone.org) (sync en los dos sentidos) + un script de [AutoHotkey v2](https://www.autohotkey.com).

## ✨ Qué hace

- 🔄 **Sincroniza en los dos sentidos** entre todas tus PCs, automáticamente.
- 🚦 **Ícono en la bandeja que cambia de color**: 🔵 sincronizando · 🟢 al día · 🔴 error · 🟠 conflicto.
- 🕹️ **Pestaña Partidas** con una tarjeta por juego, capturas y **restauración de versiones anteriores** de un state.
- 🛟 **Respaldo de todo** lo que una sync reemplaza o borra, más **copias de conflictos**: no se pierde nada.
- 🛡️ **Protección contra borrados**: frena una sync que borraría demasiado.
- 🚫 **Exclusiones** (logs, shaders, cachés…) por carpeta, elegidas en un **árbol con casillas**.
- 🧭 **Rutas portátiles** (`%DOCUMENTS%\…`) y **Agregar desde la nube** para PCs con otro nombre de usuario.
- 🗂️ Cómodo con **decenas de carpetas**: búsqueda, estado por carpeta y menús de desborde.
- ☁️ **Muchas nubes**: OneDrive, Dropbox, MEGA / Google Drive (con su app), pCloud, Box, Filen, NAS / carpeta de red, Backblaze B2, Nextcloud…

## 🚀 Instalación (en cada PC)

No necesita permisos de administrador.

1. 📦 Descomprime la carpeta `SyncDood` donde quieras.
2. 🖱️ Doble clic a **`Install.bat`**. Descarga rclone y AutoHotkey v2 (portátiles, dentro de la misma carpeta) y abre la app. Si detecta ajustes anteriores de SyncDood / RSY / SaveSync en el equipo, te ofrece una **instalación limpia** (equivale a *Desinstalar SyncDood…*: borra ajustes, historial, log, credenciales de la nube guardadas en esa PC y los registros de rclone; pregunta si conservar los respaldos; no toca tu nube ni tus carpetas de saves/states).
3. 🧙 El asistente te pide: tu carpeta de **SAVES**, tu carpeta de **STATES**, *(opcional)* otras carpetas, y tu **nube** (muestra solo lo que esa nube necesita; en las más fáciles basta con iniciar sesión una vez en el navegador). En el diálogo de carpetas puedes **escribir o pegar la ruta** en la barra de direcciones.
4. ✅ Listo: configura el inicio con Windows y hace la primera sincronización sola.

📁 Las carpetas pueden estar en rutas distintas en cada PC. Lo que debe coincidir es la **nube** y el **nombre** de cada carpeta (`saves`, `states`, o como hayas llamado a las extra).

🧭 **Misma carpeta, otro nombre de usuario.** Si agregas una carpeta que está dentro de tu carpeta de usuario de Windows (por ejemplo `C:\Users\Ana\Documents\Mi Juego`), SyncDood te ofrece guardarla como **`%DOCUMENTS%\Mi Juego`**, así la misma ubicación sirve en una PC cuyo usuario se llama distinto. Tokens disponibles: `%DOCUMENTS%`, `%SAVEDGAMES%`, `%DESKTOP%`, `%APPDATA%`, `%LOCALAPPDATA%`, `%USERPROFILE%` (cualquier otra variable de Windows también sirve). También puedes escribirlos directo en el cuadro de la ruta. En una PC nueva usa *Carpetas → Agregar desde la nube…*: lista las carpetas que ya existen en tu nube y solo te pregunta dónde va cada una en esa PC.

**Primera sincronización:** esta PC se junta con la nube. Lo que exista en un solo lado se copia al otro; si un archivo está en los dos, gana el **más nuevo** y el perdedor va a los respaldos. Puedes instalar en tus PCs en cualquier orden. ¿Prefieres que siempre gane un lado? *Opciones → Primera sincronización: quién gana* (el más nuevo · esta PC · la nube).

**¿Vienes de RSY o SaveSync?** 🔁 SyncDood es el nuevo nombre. Al abrirlo por primera vez mueve tu configuración vieja (`%LOCALAPPDATA%\RSY` o `\SaveSync`) a `%LOCALAPPDATA%\SyncDood` y conserva tu nube y carpetas tal cual. El acceso directo de inicio se recrea. Después puedes borrar la carpeta vieja y el `.exe` viejo.

## ☁️ ¿Qué nube elijo?

⭐ = la más fácil. El espacio gratis es aproximado y cambia con el tiempo.

| Nube | Qué pide | Notas |
|---|---|---|
| ⭐ **OneDrive** | Solo iniciar sesión | ~5 GB gratis, viene con Windows. Con cuentas de trabajo o escuela, si el navegador dice **«se requiere aprobación del administrador»**, usa otra nube. |
| **Dropbox** | Solo iniciar sesión | ~2 GB gratis. |
| ⭐ **Carpeta de la app de tu nube** | Elegir una carpeta | La forma fácil de usar **MEGA** (20 GB gratis, el que más da), **Google Drive** (15 GB), iCloud y similares con su app de escritorio. |
| **Carpeta de red / NAS / tu servidor** | Elegir una carpeta | Sin cuentas ni claves, p. ej. `\\MiNAS\saves` o `Z:\saves`. |
| **pCloud** | Solo iniciar sesión | ~5 GB al inicio (~10 GB con tareas/invitaciones). |
| **Box** | Solo iniciar sesión | ~10 GB gratis; máximo 250 MB por archivo. |
| Filen *(avanzado)* | Correo, contraseña y API key | 10 GB gratis, cifrado de extremo a extremo. Requiere rclone 1.73+. |
| Google Drive directo *(avanzado)* | Tu propio ID y secreto de cliente | Google retira el acceso simple de rclone en 2026. |
| Backblaze B2 *(avanzado)* | keyID, applicationKey y bucket | Para usuarios técnicos. |
| Nextcloud / ownCloud *(avanzado)* | Servidor, usuario y contraseña de app | Tu propio servidor o NAS compatible. |
| Otra *(avanzado)* | El asistente manual de rclone | Crea un remote llamado `syncdood`. |

⚠️ Toda nube debe conservar la **fecha de modificación** de los archivos (de eso depende «gana el más nuevo»). MEGA conectado directo a rclone no la maneja bien: usa MEGA con su app de escritorio mediante *Carpeta de la app de tu nube*.

<details>
<summary>📂 <b>Carpeta de la app de tu nube</b> (recomendada para MEGA y Google Drive)</summary>

1. Instala la app (*MEGA*, *Google Drive para escritorio*…) e inicia sesión.
2. En SyncDood elige **Carpeta de la app de tu nube** y selecciona una carpeta dentro de ella. SyncDood crea ahí una subcarpeta `SyncDood`.
3. Repite en cada PC con la **misma cuenta**.

**MEGA, paso a paso:** instala la app de escritorio de MEGA e inicia sesión · en la app crea una sincronización entre una carpeta local nueva (por ejemplo `C:\MEGA\SyncDood-hub`) y una carpeta nueva de tu MEGA · en SyncDood elige *Carpeta de la app de tu nube* y selecciona esa carpeta local · en las demás PCs repite con la misma cuenta y espera a que la app de MEGA termine de bajar antes de la primera sincronización. Ojo con la cuota de transferencia de las cuentas gratuitas.

Ojo: la app de la nube debe estar abierta, y la carpeta debe estar disponible sin conexión (Google Drive: *Reflejar archivos*; OneDrive: *Mantener siempre en este dispositivo*). Los cambios tardan un poco más en llegar porque ocurren dos sincronizaciones seguidas.
</details>

<details>
<summary>🖥️ <b>Carpeta de red, NAS o tu propio servidor</b></summary>

1. Comparte una carpeta (SMB/Samba: Windows, Synology, QNAP, TrueNAS, Linux con Samba…).
2. Comprueba que puedes abrirla desde el Explorador (`\\MiNAS\saves`) o asígnale una letra de unidad.
3. En SyncDood elige **Carpeta de red, NAS o tu propio servidor** y selecciónala (o pega la ruta). SyncDood crea dentro una subcarpeta `SyncDood`.
4. Repite en cada PC apuntando a la **misma carpeta compartida**.

Si el NAS está apagado o estás fuera de casa, la sync falla y se reintenta en la siguiente ronda; no se pierde nada. Para llegar a él desde fuera: una VPN a tu red, o instala Nextcloud y usa la opción *Nextcloud / ownCloud*.
</details>

<details>
<summary>🔐 <b>Filen directo</b> (avanzado)</summary>

rclone necesita tu correo, tu contraseña y una **API key**, que Filen solo da con su herramienta de línea de comandos (una vez por cuenta):

1. Descarga la [CLI de Filen](https://docs.cli.filen.io/) (no tiene que quedarse instalada).
2. Inicia sesión y ejecuta `export-api-key`. Copia la clave.
3. En SyncDood elige **Filen (avanzado)** y pega correo, contraseña y clave. Repite en cada PC.

Requiere **rclone 1.73+** (`Install.bat` / `Build.bat` bajan el actual; reemplaza un `rclone.exe` más viejo). Si cambias tu contraseña de Filen, exporta la clave otra vez y vuelve a poner los tres datos en *Nube*.
</details>

<details>
<summary>🔑 <b>Google Drive directo</b> (avanzado)</summary>

Google retira la app compartida de rclone durante 2026, así que necesitas tus propias credenciales:

1. En [console.cloud.google.com](https://console.cloud.google.com) crea un proyecto.
2. Activa la **API de Google Drive**.
3. *Pantalla de consentimiento OAuth*: **Externo**, añade tu correo como usuario de prueba y **publica la app («En producción»)**; en «Pruebas» el acceso caduca a los 7 días.
4. *Credenciales → Crear credenciales → ID de cliente de OAuth* → **App de escritorio**.
5. Pega el *ID de cliente* y el *secreto* en el asistente.

¿Aviso de «app no verificada»? Es tu propia app, continúa. ¿Demasiado trabajo? Usa *Carpeta de la app de tu nube*.
</details>

## 🪟 La ventana

**Doble clic al ícono de la bandeja** para abrirla. **Clic derecho** para el menú: *Abrir SyncDood*, *Sincronizar ahora*, abrir carpetas / log, *Buscar actualizaciones*, *Acerca de / Créditos*, *Apoyar en Patreon*, *Proyecto en GitHub*, *Iniciar con Windows*, *Salir*.

Siete pestañas. Los cambios en carpetas, nube y opciones reinician SyncDood solos. El tema (claro / oscuro) sigue a Windows, o elígelo en *Opciones → Apariencia*.

| Pestaña | Para qué sirve |
|---|---|
| 📊 **Estado** | El color del encabezado lo resume (🔵🟢🟠🔴), última sync, próxima revisión, barra de progreso, cada carpeta con su botón **Sincronizar** y la actividad reciente. |
| 📜 **Historial** | Los últimos 200 eventos por carpeta, con filtro: ↑ Subido · ↓ Bajado · ✕ Borrado · ⚠ Conflicto · ✖ Falló. |
| 🕹️ **Partidas** | Tus states, juego por juego. Mira abajo. |
| 📁 **Carpetas** | Agregar carpetas (también **desde la nube**), cambiarlas, quitarlas y abrirlas · búsqueda y estado por carpeta, cómodo con decenas de carpetas · **sincronizar solo la elegida** · **opciones y exclusiones** (árbol con casillas, carpetas vacías) · *Primera sincronización / reparar*. |
| ☁️ **Nube** | Muestra la nube actual, **cámbiala** y **prueba la conexión**. |
| ⚙️ **Opciones** | Idioma, apariencia, intervalo, proceso del emulador, esperas, quién gana en la primera sync, respaldos, inicio, actualizaciones, modo de prueba, nombre de la PC. |
| ℹ️ **Acerca de** | Versión, créditos y *Buscar actualizaciones*. |

💡 El historial sale del propio log de rclone, así que muestra lo que rclone realmente decidió. Una ↓ significa que **la nube tenía una versión distinta** (normalmente guardada desde otra PC).

📌 El **nombre** de una carpeta es su subcarpeta en la nube y debe ser igual en todas las PCs; la ruta local puede cambiar.

### 🕹️ Pestaña Partidas

- 🃏 **Una tarjeta por juego** (captura, emulador y número de states). Busca por nombre o emulador, ordena A–Z o por más reciente.
- 🔍 **Doble clic a un juego** para ver sus slots: captura, fecha, **origen** (el nombre de la PC que lo subió) y tamaño.
- 🎛️ **States reconocidos:** **RetroArch** (`.state`, `.state1`… `.state.auto` + su `.png`), **DuckStation** (`SLUS-00594_1.sav` en una carpeta `savestates`), **PCSX2** (`.p2s`), **Dolphin** (`.s01`–`.s10`), **Azahar** (`.cst`), **PPSSPP** (`.ppst` + `.jpg`). Agrega la carpeta de states de cada emulador en *Carpetas* como cualquier otra.
- ⏪ **Versiones anteriores / Restaurar…**: elige un slot (o doble clic) para listar las copias que SyncDood **ya guarda** en los respaldos (las de esta PC, y con *Incluir respaldos de la nube* también las de la nube), cada una con su captura. **Restaurar** primero guarda el state actual en los respaldos (para que puedas deshacer), deja la versión elegida como la más nueva y llega a tus otras PCs en la siguiente sync.
- 🔎 **Ampliar / Comparar…**: vista grande de la captura actual junto a la versión elegida, para comparar antes de restaurar.
- 🏷️ **Nombres reales:** algunos emuladores guardan el juego como un ID (serial / title ID).
  - **Renombrar juego…** le pone un nombre legible (se guarda en `%LOCALAPPDATA%\SyncDood\gamenames.ini`, una línea `ID=Nombre`, p. ej. `SLUS-00594=Final Fantasy VII`; también puedes editar el archivo a mano).
  - **Buscar nombres** busca los nombres de los juegos que aún muestran un ID: DuckStation con la lista de libretro/Redump, Dolphin con GameTDB. Solo descarga cuando lo pulsas y **tus nombres siempre ganan**. Los IDs de Azahar y PPSSPP solo se pueden renombrar a mano.
- 🧹 **Depurar versiones…** borra versiones viejas de states **en esta PC y en la nube**, avisando antes cuántas son. Tú eliges cuántos días conservar.
- 🖥️ **Nombre de origen:** se define en *Opciones → Nombre de esta PC* (por defecto, el nombre del equipo en Windows). Lo único extra que se guarda es una pequeña lista de texto por PC con los states que subió (en la nube, en `_pcs/`, fuera de tus carpetas sincronizadas).

<details>
<summary>🚫 <b>Emuladores sin states en archivos</b></summary>

No aparecen en Partidas, pero sus partidas normales sí se sincronizan si agregas su carpeta en *Carpetas*: **Ryujinx/Ryubing** y **Cemu** no tienen save states; **RPCS3** y **Vita3K** (solo partidas); **TeknoParrot** depende de cada juego; **Xemu** guarda snapshots dentro del disco `.qcow2`, así que no se pueden listar por slot.
</details>

<details>
<summary>🗂️ <b>Carpetas vacías</b></summary>

Se sincronizan como carpetas reales en las nubes que las tienen (OneDrive, Dropbox, pCloud, Nextcloud, carpeta/NAS…). **Backblaze B2** no tiene carpetas reales, así que ahí se ignoran las vacías; los emuladores recrean las que necesitan.

Es una **opción por carpeta** (activada por defecto): al agregar una carpeta, o después en *Carpetas → Opciones y exclusiones…*, el interruptor *Sincronizar también las carpetas vacías (conservar la estructura)* decide si las subcarpetas vacías también se crean en tus otras PCs. Actívalo cuando un juego o emulador necesite que exista su árbol de carpetas aunque esté vacío.
</details>

### 🚫 Exclusiones

*Carpetas → Opciones y exclusiones…* (y ese mismo panel al agregar una carpeta) muestra la carpeta como un **árbol con casillas**: quita la marca a cualquier archivo o carpeta completa que **no** quieras sincronizar (al desmarcar una carpeta se desmarca todo lo que contiene). Debajo del árbol hay un cuadro de **reglas extra**, una por línea (sintaxis de rclone, sin distinguir mayúsculas):

| Regla | Excluye |
|---|---|
| `*.log` | archivos por nombre, en cualquier subcarpeta |
| `shaders/` | cualquier carpeta llamada `shaders` y su contenido |
| `/logs/` | solo la carpeta `logs` en la raíz |
| `/xbox_hdd.qcow2` | un archivo concreto en la raíz |

Hay botones con sugerencias comunes (`*.log`, `shaders/`, `cache/`, `*.qcow2`). Lo que desmarcas en el árbol se guarda como reglas de ruta exacta (`/collections/old/`), así que árbol y reglas siempre coinciden; el árbol muestra hasta 4,000 elementos (para el resto usa las reglas).

- 🔁 Al editar las reglas, la siguiente sync vuelve a listar esa carpeta sola (junta, **gana el más nuevo**, no borra nada).
- 🔒 Lo excluido se ignora **en ambos lados y nunca se borra**: lo que ya estaba en la nube se queda (bórralo a mano para liberar espacio).
- 💻 Las reglas viven en `%LOCALAPPDATA%\SyncDood\exclude\<carpeta>.txt` y son por PC.

## ⏱️ Cuándo sincroniza

- 🏁 15 s después de abrir SyncDood.
- ⏲️ Cada pocos minutos (5 por defecto).
- 😴 ~20 s después de **despertar de la suspensión** (da tiempo a que vuelva el WiFi).
- 🕹️ ~3 s después de **cerrar el emulador** (`retroarch.exe` por defecto), para subir el último save/state.
- 🖱️ A mano: menú de la bandeja o la ventana → *Sincronizar ahora*.

Mientras el emulador vigilado está abierto **no sincroniza automáticamente** (el emulador reescribe el archivo mientras se sube, lo que causa conflictos); sincroniza justo al cerrarlo. Aun así puedes pulsar *Sincronizar ahora* cuando quieras (en *Opciones → «No sincronizar automáticamente mientras el emulador está abierto»* se activa o desactiva).

Si una sync falla (por ejemplo, sin internet al despertar), reintenta dos veces con 45 s de diferencia antes de avisarte y luego sigue intentando con el temporizador normal.

## 🛟 Conflictos y respaldos

Un **conflicto** = el mismo archivo cambió en **las dos PCs** desde la última sync.

1. 🏆 Gana la versión **más nueva** y conserva su nombre normal en ambas PCs.
2. 📦 La perdedora **se mueve a los respaldos**, no se pierde: `<backupDir>\<carpeta>\conflicts\<fecha_hora>\...`
3. 🔶 El ícono parpadea entre rojo y ámbar (sin ventanas emergentes) y aparece un evento ⚠ en el Historial. Abrir la ventana cuenta como revisado.

Además, todo lo que la sync **borra o sobrescribe** se respalda **por día**, en la PC (`<backupDir>\<carpeta>\<yyyy-MM-dd>\`) y en la nube (`_backup/<carpeta>/<yyyy-MM-dd>/`).

- 🧽 Los respaldos locales se limpian solos tras `backupKeepDays` (30 por defecto). Los de la nube no se borran automáticamente salvo que actives *Limpiar también respaldos y conflictos viejos de la nube* en Opciones (mismos días, como máximo una vez al día; en Backblaze B2 borra de verdad).
- 🎮 La limpieza automática **nunca borra versiones de states** (`.state`, `.state1`, `.state.auto` y sus capturas): se quedan en *Versiones anteriores* hasta que uses **Partidas → Depurar versiones…**.
- ℹ️ Los respaldos se crean cuando una **sync reemplaza o borra** un archivo, no cada vez que guardas en el emulador, y se guardan **por día**: si un archivo se reemplaza varias veces en un día, queda la copia más reciente de ese día.
- 🩹 **Para recuperar algo:** *Opciones → Abrir respaldos* (o menú de la bandeja → *Abrir carpeta de respaldos*) y copia el archivo de vuelta.

## 🔄 Actualizaciones

SyncDood consulta las *Releases* de GitHub (`kyaaadood/SyncDood`) en segundo plano, como máximo una vez al día y sin avisar si no hay nada nuevo. También puedes usar *Buscar actualizaciones* en el menú de la bandeja o en *Acerca de*. Si hay una versión más nueva, ofrece abrir la página de descarga. Se desactiva en *Opciones*.

<details>
<summary>🏷️ <b>Publicar una versión nueva</b> (para quien desarrolla)</summary>

La versión vive en **un solo lugar**: la línea `AppVersion` al inicio de `SyncDood.ahk` (ahora `"0.2"`).

1. Cambia `AppVersion` (p. ej. `"0.2"`).
2. Crea una *Release* en GitHub en `kyaaadood/SyncDood` con el mismo número y una `v` delante (`v0.2`).
3. Las copias en uso comparan esa etiqueta con su `AppVersion` y ofrecen la descarga si la etiqueta es más nueva.

`Build.bat` también lee `AppVersion` y la escribe en las propiedades de `SyncDood.exe`.
</details>

<details>
<summary>📦 <b>Crear un solo <code>SyncDood.exe</code></b></summary>

Para repartir **un solo archivo** (sin Install.bat, sin instalar AutoHotkey, sin descargas en la PC de destino):

1. En Windows, doble clic a **`Build.bat`**.
2. La primera vez descarga rclone, AutoHotkey v2 y Ahk2Exe (en caché en `build\cache`) y compila.
3. Obtienes **`dist\SyncDood.exe`**. Cópialo a cualquier PC y ábrelo: aparece el asistente de siempre.

Lleva dentro el runtime de AutoHotkey, el script, `rclone.exe` y los íconos. Al abrirse desempaca rclone y los íconos en `%LOCALAPPDATA%\SyncDood\bin` (solo cuando cambia la versión). Los ajustes quedan en `%LOCALAPPDATA%\SyncDood\`.

A tener en cuenta:
- ⚖️ Pesa ~60 MB, casi todo rclone.
- 📌 Deja el `.exe` en una carpeta fija (p. ej. `C:\Programas\SyncDood`): el inicio con Windows apunta ahí. Si lo mueves, desactiva y vuelve a activar *Iniciar con Windows*.
- 🔁 Para actualizar rclone, borra `build\cache\rclone.exe` y ejecuta `Build.bat` otra vez.
- 🛡️ El `.exe` no está firmado: SmartScreen puede avisar la primera vez («Más información → Ejecutar de todas formas») y algunos antivirus marcan por error los ejecutables de AutoHotkey. Añade una excepción o compílalo tú en esa PC.
- 🌐 Si tu red bloquea las descargas, pon `rclone.exe`, `AutoHotkey64.exe` (v2) y `Ahk2Exe.exe` en `build\cache`.
</details>

## 🎨 Íconos

El logo es una **S** que cambia de color según el estado de la sincronización:

| Ícono | Significado |
|---|---|
| 🔵 Azul | Sincronizando |
| 🟢 Verde | Todo al día (el tooltip muestra la hora y cuántos archivos subieron ↑ y bajaron ↓) |
| 🔴 Rojo | La sincronización falló (el tooltip dice por qué) |
| 🔴↔🟠 Rojo ↔ ámbar (parpadea) | Hay un conflicto sin revisar; deja de parpadear al abrir la ventana |

<details>
<summary>🖌️ <b>Regenerar los íconos</b></summary>

```
python tools/make_icons.py
```

Requiere [Pillow](https://python-pillow.org). Genera `icons/ok.ico`, `syncing.ico`, `error.ico` y `conflict.ico` (y los `.png` que se usan aquí).
</details>

## ⚙️ Ajustes (`config.ini`)

Normalmente **no lo necesitas**: todo se cambia desde la ventana. Está en `%LOCALAPPDATA%\SyncDood\` junto con `sync.log` y la carpeta `data\` (botón *Abrir config.ini* en *Opciones*; si lo editas a mano, sal y vuelve a abrir SyncDood).

<details>
<summary>📋 <b>Todas las claves</b></summary>

| Clave | Qué hace | Por defecto |
|---|---|---|
| `language` | `auto` (idioma de Windows), `en` o `es` | `auto` |
| `firstSyncWins` | Quién gana la primera sync: `newer`, `local`, `cloud` | `newer` |
| `intervalMin` | Minutos entre revisiones | `5` |
| `watchProcess` | Proceso del emulador; sincroniza al cerrarse (vacío = desactivado) | `retroarch.exe` |
| `resumeDelaySec` | Segundos de espera tras despertar de la suspensión | `20` |
| `pcName` | Nombre de esta PC, que se muestra como origen de tus states (vacío = nombre del equipo en Windows) | *(vacío)* |
| `parallelOverride` | Archivos transferidos a la vez (1-32; las revisiones corren al doble). `0` = automático: 8 para Backblaze B2, Nextcloud, carpeta y NAS, 4 para el resto (más puede hacer que Google Drive, OneDrive o Dropbox te limiten). Se cambia en Opciones (Auto / Manual); al cambiar de nube vuelve a automático | `0` |
| `maxDeletePct` | Protección contra borrados: una sync que borraría más de este % de los archivos de una carpeta se detiene antes de tocar nada. Un *Sincronizar ahora* manual muestra qué se borraría (esta PC / nube) y pregunta si continuar; las automáticas solo dejan esa carpeta detenida. `0` = desactivado | `25` |
| `pruneCloudBackups` | `1` también limpia respaldos y conflictos viejos en la nube (`_backup/`), con los mismos días de `backupKeepDays`, como máximo una vez al día. Las versiones de states se quedan; tus carpetas sincronizadas nunca se tocan. En Backblaze B2 borra de verdad (libera espacio) | `0` |
| `backupDir` | Carpeta de respaldos locales (fuera de las carpetas sincronizadas) | `%LOCALAPPDATA%\SyncDood\backups` |
| `backupKeepDays` | Días que se guardan los respaldos locales (`0` = para siempre) | `30` |
| `checkUpdates` | `1` = buscar actualizaciones al abrir | `1` |
| `dryRun` | `1` = modo de prueba: solo escribe en `sync.log` lo que haría | `0` |
| `settleSec` | Segundos que un archivo debe quedar sin tocar antes de sincronizarlo (espera hasta ~45 s; `0` = no esperar) | `10` |
| `theme` | `auto` (sigue a Windows), `light` o `dark` | `auto` |
| `pauseWhileRunning` | `1` = sin syncs automáticas mientras el emulador vigilado está abierto (sincroniza al cerrarlo) | `1` |

Con *Carpeta de la app de tu nube* la ruta puede ser distinta en cada PC; lo que debe coincidir es la cuenta de la nube.
</details>

## 🧹 Desinstalar y limpiar

*Ventana → Opciones*:

- 🗑️ **Desinstalar SyncDood…** quita el acceso directo de inicio, `%LOCALAPPDATA%\SyncDood` (ajustes, historial, log), la conexión de rclone a tu nube (las credenciales guardadas en esta PC), los registros de sincronización de rclone de SyncDood y cualquier resto de RSY / SaveSync. Pregunta aparte si borrar los respaldos locales y el programa (en scripts sueltos solo se quitan los archivos propios de SyncDood, nunca toda la carpeta). **Nunca toca tu nube (archivos ni su carpeta `SyncDood`) ni tus carpetas de saves/states.**

Los `.exe` viejos (donde los hayas puesto) y cualquier carpeta `SaveSync` / `RSY` dentro de tu nube no se borran solos; quítalos a mano si ya no los necesitas.

## 🆘 Problemas comunes

<details>
<summary>Abrir la lista</summary>

- **Install.bat se cierra o no puede ejecutar scripts:** la política del equipo puede bloquear PowerShell. Pon `rclone.exe` junto a `SyncDood.ahk`, instala [AutoHotkey v2](https://www.autohotkey.com/) y abre `SyncDood.ahk` directamente.
- **Las descargas están bloqueadas:** baja `rclone.exe` de [rclone.org/downloads](https://rclone.org/downloads/), ponlo junto a `SyncDood.ahk` e instala AutoHotkey v2 aparte.
- **Backblaze B2 dice que superaste el límite diario:** son los topes diarios de la cuenta (descargas y operaciones). Se reinician a las 12:00 AM GMT (6:00 PM en México). Mientras tanto cierra SyncDood para no gastarlos de nuevo, y revisa en *Caps & Alerts* de tu cuenta si quieres subirlos. Una carpeta mal configurada o muy grande los agota rápido.
- **Ícono rojo pidiendo «Primera sincronización / reparar»:** una sync se interrumpió en mal momento, o algo se movió/borró a mano. *Ventana → Carpetas → Primera sincronización / reparar…*
- **El encabezado muestra un error pero está cortado:** pulsa **Detalles** (arriba a la derecha) para ver el mensaje completo y las últimas líneas de error de `sync.log`.
- **«cannot find prior Path1 or Path2 listings» en el log:** rclone no tiene registro de sync de esa carpeta y esa nube (por ejemplo tras migrar o cambiar el nombre de la nube). SyncDood lo detecta y hace una primera sincronización solo (junta ambos lados, no borra nada).
- **`.syncconflict1` en un state/save mientras juegas:** el emulador reescribe el archivo mientras rclone lo sube. No se pierde nada: se queda la copia más nueva y la otra va a *respaldos → conflicts*. SyncDood lo evita no sincronizando automáticamente mientras el emulador está abierto.
- **Ver el log:** menú de la bandeja → *Abrir log* (`sync.log`, guarda solo los últimos 2 días).
- **Borrar un save a mano** llega a las otras PCs en la siguiente sync (así funciona la sync en los dos sentidos), pero queda respaldado. Si borras más del 50% de los archivos de golpe, rclone se niega a sincronizar como protección.
</details>

## 📝 Bueno saber

- 🕐 Mantén bien la hora de tus PCs («gana el más nuevo» depende de las fechas de los archivos).
- 📏 Los states pesan más que los saves: cuida el espacio de tu nube (y de los respaldos).
- 🚫 Evita jugar el mismo juego en dos PCs a la vez: el conflicto se detecta, pero una de las dos sesiones quedará solo como respaldo.
- 🧪 `rclone bisync` está marcado como *beta* por el proyecto rclone. Funciona bien con carpetas pequeñas, pero guarda una copia aparte de tus saves de vez en cuando.
- 🌍 Los textos siguen el idioma de Windows (español si Windows está en español, inglés en otro caso; puedes forzarlo en *Opciones*).

## 💛 Créditos

Hecho por **KyaaaDood** con Claude AI. 🤖✨

Sigue mi trabajo en [GitHub](https://github.com/kyaaadood) y, si quieres apoyar el proyecto, puedes hacerlo en [Patreon](https://www.patreon.com/cw/KyaaaDood). ☕

SyncDood usa [rclone](https://rclone.org) (licencia MIT) y [AutoHotkey v2](https://www.autohotkey.com) (GPLv2); mira [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
