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

# ------------------------------------------------------------- Open app ----
Say (L "Abriendo SyncDood. Si es la primera vez, te pedira tus carpetas y tu nube." "Opening SyncDood. If this is the first time, it will ask for your folders and your cloud.")
Start-Process -FilePath $ahk -ArgumentList ('"' + (Join-Path $here 'SyncDood.ahk') + '"')
