<#
.SYNOPSIS
  RustDesk ID Server - Magisk module one-click installer (Windows)
.DESCRIPTION
  Automatically install the RustDesk hbbs ID server (optional hbbr relay)
  to any rooted Android phone with Magisk. Detects adb, generates a random
  key, packs the module, pushes it to the phone and deploys it into the
  Magisk modules directory.
.EXAMPLE
  .\install.ps1                       # auto-generate a random key and install
  .\install.ps1 -Key mykey123         # install with a fixed key
  .\install.ps1 -Relay                # also enable the hbbr relay server
  .\install.ps1 -Serial 0123456789    # target a specific device serial
  .\install.ps1 -OutOnly .\mod.zip    # only pack the module, do not install
#>
[CmdletBinding()]
param(
    [string]$Key,          # specify the key; defaults to a random value
    [string]$Serial,       # target device serial
    [switch]$Relay,        # enable the relay server
    [string]$OutOnly,      # only pack (no install); value is output zip path
    [switch]$Force         # force overwrite install (keeps data)
)

# External commands (adb) write diagnostics to stderr; keep going and rely on
# $LASTEXITCODE checks instead of letting stderr terminate the script.
$ErrorActionPreference = 'Continue'

# ---------- paths ----------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# install.ps1 lives at the module root, so the root is the script dir
$Root = $ScriptDir   # module root (contains module.prop, config, bin, ...)
$EnvFile = Join-Path $Root "config\env.sh"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "    [!] $msg" -ForegroundColor Yellow }

# ---------- 1. locate adb ----------
Write-Step "Locating adb"
function Find-Adb {
    $c = Get-Command adb -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\platform-tools\adb.exe",
        "$env:ProgramFiles\Android\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools*\platform-tools\adb.exe"
    )
    foreach ($p in $candidates) {
        $found = Get-ChildItem $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}
$Adb = Find-Adb
if (-not $Adb) {
    Write-Warn "adb not found. Install Android platform-tools first:"
    Write-Warn "  https://developer.android.com/tools/releases/platform-tools"
    Write-Warn "  or run:  winget install Google.PlatformTools"
    exit 1
}
Write-OK "adb path: $Adb"

# ---------- 2. choose device ----------
Write-Step "Detecting devices"
& $Adb start-server | Out-Null
Start-Sleep -Milliseconds 500
if ($Serial) {
    $DeviceList = @($Serial)
} else {
    $raw = & $Adb devices
    $DeviceList = @($raw | Select-String '^([a-zA-Z0-9_-]+)\s+device' | ForEach-Object { ($_ -split '\s+')[0] })
}
if ($DeviceList.Count -eq 0) {
    Write-Warn "No authorized Android device detected."
    Write-Warn "  1) Enable Developer options -> USB debugging on the phone"
    Write-Warn "  2) Connect the data cable and authorize (tap Allow)"
    Write-Warn "  3) Set USB mode to File transfer (MTP)"
    exit 1
}
$Device = $DeviceList[0]
if ($DeviceList.Count -gt 1) {
    Write-Host "Multiple devices detected:"
    for ($i=0; $i -lt $DeviceList.Count; $i++) { Write-Host "  [$i] $($DeviceList[$i])" }
    $sel = Read-Host "Choose device index [default 0]"
    if ($sel -ne '' -and [int]$sel -lt $DeviceList.Count) { $Device = $DeviceList[[int]$sel] }
    else { $Device = $DeviceList[0] }
}
Write-OK "Target device: $Device"
& $Adb -s $Device wait-for-device

# ---------- 3. check root / Magisk ----------
Write-Step "Checking root (su) and Magisk"
$suCheck = & $Adb -s $Device shell "su -c 'id -u'" 2>$null
if ($suCheck.Trim() -ne '0') {
    Write-Warn "No root on this device. Confirm:"
    Write-Warn "  1) The phone is rooted (Magisk installed and working)"
    Write-Warn "  2) adb shell was granted superuser access"
    exit 1
}
Write-OK "root available"
$magiskCheck = & $Adb -s $Device shell "su -c 'ls /data/adb/magisk/magisk 2>/dev/null || echo NO_MAGISK'" 2>$null
if ($magiskCheck -match 'NO_MAGISK') {
    Write-Warn "Magisk not detected. Install Magisk and root the phone first."
    exit 1
}
Write-OK "Magisk installed"

# ---------- 4. generate key ----------
Write-Step "Configuring key"
if (-not $Key) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $rnd = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $buf = New-Object byte[] 32
    $rnd.GetBytes($buf)
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $buf) { [void]$sb.Append($chars[$b % $chars.Length]) }
    $Key = $sb.ToString()
}
Write-OK "server key: $Key"
Write-Warn "Record this key. Clients must use the same value."

# ---------- 5. write config ----------
Write-Step "Writing config to config/env.sh"
if (-not (Test-Path $EnvFile)) {
    Write-Warn "Cannot find $EnvFile"
    exit 1
}
$envContent = Get-Content $EnvFile -Raw -Encoding UTF8
$envContent = $envContent -replace 'SERVER_KEY="[^"]*"', "SERVER_KEY=""$Key"""
$envContent = $envContent -replace 'ENABLE_RELAY=[0-1]', "ENABLE_RELAY=$(if ($Relay) {1} else {0})"
[System.IO.File]::WriteAllText($EnvFile, $envContent, (New-Object System.Text.UTF8Encoding($false)))
Write-OK "config written"

# ---------- 6. pack ----------
Write-Step "Packing Magisk module"
$stage = Join-Path $env:TEMP ("rdmod_" + [guid]::NewGuid().ToString('N'))
$stageBin = Join-Path $stage "bin"
New-Item -ItemType Directory -Force -Path $stageBin | Out-Null
$tmpZip = Join-Path $env:TEMP ("rdmod_" + [guid]::NewGuid().ToString('N') + ".zip")

Copy-Item (Join-Path $Root "module.prop") (Join-Path $stage "module.prop")
Copy-Item (Join-Path $Root "service.sh")   (Join-Path $stage "service.sh")
Copy-Item (Join-Path $Root "customize.sh") (Join-Path $stage "customize.sh")
Copy-Item (Join-Path $Root "uninstall.sh") (Join-Path $stage "uninstall.sh")
Copy-Item (Join-Path $Root "README.md")    (Join-Path $stage "README.md")
Copy-Item (Join-Path $Root "config")       (Join-Path $stage "config") -Recurse

$arch = (& $Adb -s $Device shell "getprop ro.product.cpu.abi" 2>$null).Trim()
Write-Host "    device arch: $arch"
$binArch = "arm64"
if ($arch -match 'armeabi|armv7') { $binArch = "arm" }
elseif ($arch -match 'x86_64')   { $binArch = "x86_64" }
elseif ($arch -match 'x86')      { $binArch = "x86" }
Write-OK "using binary arch: $binArch"
$srcBin = Join-Path $Root "bin\$binArch"
if (-not (Test-Path (Join-Path $srcBin "hbbs"))) {
    Write-Warn "Missing $srcBin\hbbs binary. Add it first."
    exit 1
}
Copy-Item $srcBin (Join-Path $stageBin $binArch) -Recurse

# ---- custom zip with forward-slash paths (Android unzip compatible) ----
function New-ModuleZip {
    param([string]$SourceDir, [string]$DestZip)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $DestZip) { Remove-Item $DestZip -Force }
    $fs = [System.IO.File]::Open($DestZip, [System.IO.FileMode]::CreateNew)
    $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $base = (Resolve-Path $SourceDir).Path.TrimEnd('\')
        Get-ChildItem $SourceDir -Recurse -File | ForEach-Object {
            # relative entry path, always forward slashes
            $rel = $_.FullName.Substring($base.Length).TrimStart('\')
            $entryName = $rel.Replace('\', '/')
            $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $es = $entry.Open()
            try {
                $in = [System.IO.File]::OpenRead($_.FullName)
                try { $in.CopyTo($es) } finally { $in.Dispose() }
            } finally { $es.Dispose() }
        }
    } finally {
        $archive.Dispose()
        $fs.Dispose()
    }
}
New-ModuleZip -SourceDir $stage -DestZip $tmpZip
Write-OK "packed: $tmpZip ($([math]::Round((Get-Item $tmpZip).Length/1MB,2)) MB)"

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 7. OutOnly ----------
if ($OutOnly) {
    Copy-Item $tmpZip $OutOnly -Force
    Remove-Item $tmpZip -Force
    Write-Step "Pack only done"
    Write-OK "module zip: $OutOnly"
    Write-OK "server key: $Key"
    exit 0
}

# ---------- 8. push and deploy ----------
Write-Step "Pushing to phone and deploying"
$remote = "/data/local/tmp/rustdesk-module.zip"
& $Adb -s $Device push $tmpZip $remote 2>$null
if ($LASTEXITCODE -ne 0) { Write-Warn "push failed"; exit 1 }

$rmOld = if ($Force) { "rm -rf /data/adb/modules/rustdesk_id_server" }
         else { "rm -rf /data/adb/modules/rustdesk_id_server/service.sh /data/adb/modules/rustdesk_id_server/bin /data/adb/modules/rustdesk_id_server/config /data/adb/modules/rustdesk_id_server/customize.sh /data/adb/modules/rustdesk_id_server/uninstall.sh /data/adb/modules/rustdesk_id_server/module.prop" }
& $Adb -s $Device shell "su -c '$rmOld'" 2>$null
& $Adb -s $Device shell "su -c 'mkdir -p /data/adb/modules/rustdesk_id_server && unzip -o $remote -d /data/adb/modules/rustdesk_id_server && chmod 755 /data/adb/modules/rustdesk_id_server/service.sh /data/adb/modules/rustdesk_id_server/customize.sh /data/adb/modules/rustdesk_id_server/uninstall.sh /data/adb/modules/rustdesk_id_server/bin/*/hbbs /data/adb/modules/rustdesk_id_server/bin/*/hbbr'" 2>$null
if ($LASTEXITCODE -ne 0) { Write-Warn "deploy failed"; exit 1 }
& $Adb -s $Device shell "su -c 'rm -f $remote'" 2>$null | Out-Null
Write-OK "module deployed to /data/adb/modules/rustdesk_id_server/"

# ---------- 9. start ----------
Write-Step "Starting hbbs service"
& $Adb -s $Device shell "su -c 'sh /data/adb/modules/rustdesk_id_server/service.sh'" 2>$null
Start-Sleep 2

# ---------- 10. verify ----------
Write-Step "Verifying runtime"
$hbbsProc = & $Adb -s $Device shell "su -c 'pgrep -x hbbs && echo RUNNING'" 2>$null
$ports = & $Adb -s $Device shell "su -c 'ss -tulnp 2>/dev/null | grep hbbs'" 2>$null
$wlan0 = & $Adb -s $Device shell "ip -4 addr show wlan0 2>/dev/null" 2>$null
$mIp = [regex]::Match(($wlan0 -join "`n"), 'inet\s+([0-9.]+)')
if (-not $mIp.Success) {
    $all = & $Adb -s $Device shell "ip -4 addr show 2>/dev/null" 2>$null
    $mIp = [regex]::Match(($all -join "`n"), 'inet\s+((?!127\.0\.0\.1)[0-9.]+)')
}
$phoneIp = if ($mIp.Success) { $mIp.Groups[1].Value } else { '' }
if ($hbbsProc -match 'RUNNING') {
    Write-OK "hbbs running"
    Write-OK "ports:"
    $ports | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Warn "hbbs not running. Check log: /data/local/tmp/rustdesk/rustdesk.log"
}

# ---------- done ----------
Write-Step "Done"
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   RustDesk server deployed!" -ForegroundColor Green
Write-Host "   ============================================" -ForegroundColor Green
Write-Host "   server key  : $Key"
if ($phoneIp) { Write-Host "   phone IP    : $phoneIp" }
Write-Host "   ID server   : phone IP (e.g. $phoneIp)"
Write-Host "   Key (pub)   : $Key"
Write-Host "   Relay       : $(if ($Relay) { 'enabled (same IP)' } else { 'disabled' })"
Write-Host "   ============================================" -ForegroundColor Green
Write-Warn "  Clients use the ID server address and this Key to connect."
Write-Warn "  For public access, forward 21116(TCP+UDP), 21115(TCP) (and 21117/TCP if relay) to the phone."
