# Setup.ps1 - prepares SyncDood (no administrator rights needed)
# Downloads rclone and AutoHotkey v2 (portable, inside this folder) if you don't have them, then opens SyncDood.
# The app itself asks for your folders and cloud on first launch.
# Normal use: double-click Install.bat

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Language: Spanish if Windows is in Spanish, English otherwise (ASCII only on purpose)
$es = $false
try { $es = ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') } catch {}
function L($spanish, $english) { if ($es) { return $spanish } else { return $english } }

function Say($m) { Write-Host ("[SyncDood] " + $m) }
function Fail($m) {
    Write-Host ""
    Write-Host ("[SyncDood] ERROR: " + $m) -ForegroundColor Red
    exit 1
}

# Downloads a zip, extracts it to a temp folder and returns that folder (or $null on failure)
function Get-ZipFolder($url) {
    $tmp = Join-Path $env:TEMP ("syncdood_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'pkg.zip'
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zip -DestinationPath $tmp -Force -ErrorAction Stop
    } catch {
        return $null
    }
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    return $tmp
}

if (-not (Test-Path (Join-Path $here 'SyncDood.ahk'))) { Fail (L "No encuentro SyncDood.ahk junto a Setup.ps1." "Cannot find SyncDood.ahk next to Setup.ps1.") }

Write-Host ""
Say ((L "Preparando SyncDood en: " "Setting up SyncDood in: ") + $here)

# --------------------------------------------------------------- rclone ----
$rclone = Join-Path $here 'rclone.exe'
if (-not (Test-Path $rclone) -and -not (Get-Command rclone.exe -ErrorAction SilentlyContinue)) {
    Say (L "Descargando rclone..." "Downloading rclone...")
    $tmp = Get-ZipFolder 'https://downloads.rclone.org/rclone-current-windows-amd64.zip'
    if (-not $tmp) { Fail (L "No pude descargar rclone (red bloqueada?). Baja rclone.exe de https://rclone.org/downloads/ , ponlo en esta carpeta y vuelve a correr Install.bat." "Could not download rclone (blocked network?). Get rclone.exe from https://rclone.org/downloads/ , put it in this folder and run Install.bat again.") }
    $exe = Get-ChildItem -Path $tmp -Recurse -Filter rclone.exe | Select-Object -First 1
    if (-not $exe) { Fail (L "El zip de rclone no trae rclone.exe." "The rclone zip does not contain rclone.exe.") }
    Copy-Item $exe.FullName $rclone -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Say (L "rclone listo." "rclone ready.")

# ------------------------------------------------------- AutoHotkey v2 ----
$ahk = $null
$candidates = @(
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
    (Join-Path $here 'ahk\AutoHotkey64.exe')
)
foreach ($p in $candidates) {
    if (Test-Path $p) { $ahk = $p; break }
}
if (-not $ahk) {
    Say (L "Descargando AutoHotkey v2 (version portatil, sin instalar)..." "Downloading AutoHotkey v2 (portable version, no install)...")
    $tmp = Get-ZipFolder 'https://www.autohotkey.com/download/ahk-v2.zip'
    if (-not $tmp) { Fail (L "No pude descargar AutoHotkey v2 (red bloqueada?). Instalalo desde https://www.autohotkey.com/ y vuelve a correr Install.bat." "Could not download AutoHotkey v2 (blocked network?). Install it from https://www.autohotkey.com/ and run Install.bat again.") }
    $ahkDir = Join-Path $here 'ahk'
    New-Item -ItemType Directory -Path $ahkDir -Force | Out-Null
    Copy-Item (Join-Path $tmp '*') $ahkDir -Recurse -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $ahk = Join-Path $ahkDir 'AutoHotkey64.exe'
    if (-not (Test-Path $ahk)) { Fail (L "El zip de AutoHotkey no trae AutoHotkey64.exe." "The AutoHotkey zip does not contain AutoHotkey64.exe.") }
}
Say (L "AutoHotkey listo." "AutoHotkey ready.")

# ------------------------------------------------------- Clean install ----
# If settings from SyncDood / RSY / SaveSync exist on this PC, offer to wipe them first (same as the app's
# "Uninstall SyncDood..." but without opening it). Your cloud and your saves/states folders are NEVER touched.
$dirs = @('SyncDood', 'RSY', 'SaveSync') | ForEach-Object { Join-Path $env:LOCALAPPDATA $_ } | Where-Object { Test-Path $_ }
if ($dirs) {
    Write-Host ""
    Say (L "Encontre configuracion anterior en este equipo:" "Found previous settings on this PC:")
    $dirs | ForEach-Object { Write-Host ("   " + $_) }
    Say (L "Una instalacion limpia borra esos ajustes, el historial, el log y las credenciales de la nube guardadas aqui. NO toca tu nube ni tus carpetas de saves/states." "A clean install deletes those settings, history, log and the cloud credentials stored here. It does NOT touch your cloud or your saves/states folders.")
    $a = Read-Host (L "Hacer instalacion limpia? (S/N, Enter = N)" "Do a clean install? (Y/N, Enter = N)")
    if ($a -match '^(s|si|y|yes)$') {
        $keep = $true
        $backups = $dirs | ForEach-Object { Join-Path $_ 'backups' } | Where-Object { Test-Path $_ }
        if ($backups) {
            $b = Read-Host (L "Conservar los respaldos locales (backups)? (S/N, Enter = S)" "Keep the local backups? (Y/N, Enter = Y)")
            $keep = -not ($b -match '^(n|no)$')
        }

        Say (L "Cerrando SyncDood si esta abierto..." "Closing SyncDood if it is running...")
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'SyncDood.exe' -or $_.CommandLine -match 'SyncDood\.ahk|RSY\.ahk|SaveSync\.ahk' } |
            Where-Object { $_.ProcessId -ne $PID } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 800

        # startup shortcuts
        foreach ($n in 'SyncDood', 'RSY', 'SaveSync') {
            Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) ($n + '.lnk')) -Force -ErrorAction SilentlyContinue
        }

        # rclone connections (only the credentials stored on this PC)
        $rc = $rclone
        if (-not (Test-Path $rc)) { $rc = (Get-Command rclone.exe -ErrorAction SilentlyContinue).Source }
        if ($rc) {
            foreach ($n in 'syncdood', 'syncdood2', 'rsy', 'rsy2', 'savesync') {
                & $rc config delete $n 2>$null | Out-Null
            }
        }

        # rclone's bisync records
        $bis = Join-Path $env:LOCALAPPDATA 'rclone\bisync'
        if (Test-Path $bis) {
            foreach ($pat in '*..syncdood_*', '*..syncdood2_*', '*..rsy_*', '*..rsy2_*', '*..savesync_*', '*_SyncDood_*', '*_RSY_*') {
                Get-ChildItem -Path $bis -Filter $pat -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }

        # settings, history, log (backups only if you said so)
        foreach ($d in $dirs) {
            if ($keep) {
                Get-ChildItem -Path $d -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'backups' } |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Say (L "Listo: instalacion limpia hecha. Al abrir SyncDood te pedira carpetas y nube; la primera sincronizacion mezcla y no borra nada." "Done: clean install finished. SyncDood will ask for folders and cloud; the first sync merges and deletes nothing.")
    }
}

# ------------------------------------------------------------- Open app ----
Say (L "Abriendo SyncDood. Si es la primera vez, te pedira tus carpetas y tu nube." "Opening SyncDood. If this is the first time, it will ask for your folders and your cloud.")
Start-Process -FilePath $ahk -ArgumentList ('"' + (Join-Path $here 'SyncDood.ahk') + '"')
