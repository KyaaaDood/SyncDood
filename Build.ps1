# Build.ps1 - builds dist\SyncDood.exe (AutoHotkey + rclone + icons, all in a single file)
# Downloads the tools the first time (kept in build\cache) and compiles with Ahk2Exe.
# The exe's version is taken from AppVersion in SyncDood.ahk.
# Normal use: double-click Build.bat

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$es = $false
try { $es = ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') } catch {}
function L($spanish, $english) { if ($es) { return $spanish } else { return $english } }
function Say($m) { Write-Host ("[Build] " + $m) }

$cache = Join-Path $here 'build\cache'
$stage = Join-Path $here 'build\stage'
$dist  = Join-Path $here 'dist'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
New-Item -ItemType Directory -Path $dist -Force | Out-Null

# Downloads a zip and copies the file $name found inside it to build\cache.
function Get-Tool($name, $url) {
    $target = Join-Path $cache $name
    if (Test-Path $target) { return $target }
    Say ((L "Descargando " "Downloading ") + $name + " ...")
    $tmp = Join-Path $env:TEMP ("syncdood_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'pkg.zip'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $f = Get-ChildItem -Path $tmp -Recurse -Filter $name | Select-Object -First 1
        if (-not $f) { throw ((L "No encontre " "Could not find ") + $name + " in " + $url) }
        Copy-Item $f.FullName $target -Force
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $target
}

try {
    $src = Join-Path $here 'SyncDood.ahk'
    if (-not (Test-Path $src)) { throw (L "No encuentro SyncDood.ahk junto a Build.ps1." "Cannot find SyncDood.ahk next to Build.ps1.") }

    # --- version: read AppVersion from SyncDood.ahk ("0.1" -> "0.1.0.0" for the exe's file properties)
    $code = Get-Content $src -Raw -Encoding UTF8
    $m = [regex]::Match($code, 'AppVersion\s*:=\s*"([0-9.]+)"')
    if (-not $m.Success) { throw (L "No encuentro AppVersion en SyncDood.ahk." "Cannot find AppVersion in SyncDood.ahk.") }
    $ver = $m.Groups[1].Value
    $parts = @($ver.Split('.'))
    while ($parts.Count -lt 4) { $parts += '0' }
    $ver4 = ($parts[0..3] -join '.')
    Say ("SyncDood v" + $ver)

    # --- tools
    $rclone = Get-Tool 'rclone.exe' 'https://downloads.rclone.org/rclone-current-windows-amd64.zip'
    $base   = Get-Tool 'AutoHotkey64.exe' 'https://www.autohotkey.com/download/ahk-v2.zip'
    $ahk2exe = Join-Path $cache 'Ahk2Exe.exe'
    if (-not (Test-Path $ahk2exe)) {
        Say (L "Buscando la ultima version de Ahk2Exe ..." "Looking for the latest Ahk2Exe ...")
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest' -Headers @{ 'User-Agent' = 'SyncDood-build' }
        $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
        if (-not $asset) { throw (L "No encontre el zip de Ahk2Exe en GitHub." "Could not find the Ahk2Exe zip on GitHub.") }
        $ahk2exe = Get-Tool 'Ahk2Exe.exe' $asset.browser_download_url
    }

    # --- staging folder: script + icons + rclone.exe (FileInstall takes them from here)
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    $staged = Join-Path $stage 'SyncDood.ahk'
    $patched = [regex]::Replace($code, ';@Ahk2Exe-SetVersion\s+\S+', (';@Ahk2Exe-SetVersion ' + $ver4))
    [System.IO.File]::WriteAllText($staged, $patched, (New-Object System.Text.UTF8Encoding($true)))
    Copy-Item (Join-Path $here 'icons') (Join-Path $stage 'icons') -Recurse -Force
    Copy-Item $rclone (Join-Path $stage 'rclone.exe') -Force

    # --- compile
    $out = Join-Path $dist 'SyncDood.exe'
    if (Test-Path $out) { Remove-Item $out -Force }
    Say (L "Compilando ..." "Compiling ...")
    $compArgs = @('/in', ('"' + $staged + '"'),
              '/out', ('"' + $out + '"'),
              '/base', ('"' + $base + '"'),
              '/icon', ('"' + (Join-Path $stage 'icons\ok.ico') + '"'),
              '/silent')
    Start-Process -FilePath $ahk2exe -ArgumentList $compArgs -Wait | Out-Null
    if (-not (Test-Path $out)) { throw (L "Ahk2Exe no genero el .exe. Abre build\cache\Ahk2Exe.exe a mano para ver el error." "Ahk2Exe did not produce the .exe. Open build\cache\Ahk2Exe.exe by hand to see the error.") }

    $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host ""
    Say ((L "Listo: " "Done: ") + $out + "  (" + $mb + " MB)")
    Say (L "Es un solo archivo: copialo a cualquier PC y abrelo. No necesita nada mas." "It is a single file: copy it to any PC and open it. Nothing else needed.")
} catch {
    Write-Host ""
    Write-Host ("[Build] ERROR: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host (L "Si las descargas estan bloqueadas, pon rclone.exe, AutoHotkey64.exe (v2) y Ahk2Exe.exe en build\cache y vuelve a correr Build.bat." "If downloads are blocked, put rclone.exe, AutoHotkey64.exe (v2) and Ahk2Exe.exe in build\cache and run Build.bat again.")
    exit 1
}
