@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 3.1.2 inside
echo   it. Double-click and it installs that build into every
echo   Minecraft data folder on this PC, then keeps your worlds
echo   bound to it. No download, nothing else to copy.
echo.
echo   Drag a .mcpack onto this file to install a different build.
echo ================================================================
echo.
set "RAB_SELF=%~f0"
set "RAB_RUN_DIR=%~dp0"
set "RAB_PACK_ARG=%~1"
set "RAB_TMP=%TEMP%\rab-update-run.ps1"
set "RAB_PACK=%TEMP%\rab-update-pack.mcpack"
if not defined RAB_PACK_ARG set "RAB_PACK_ARG=%RAB_PACK%"
if exist "%RAB_TMP%" del "%RAB_TMP%" >nul 2>&1
if exist "%RAB_PACK%" del "%RAB_PACK%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $L=Get-Content -LiteralPath $env:RAB_SELF; $b=[Array]::IndexOf($L,'#@@RAB_PS_BODY@@'); $p=[Array]::IndexOf($L,'#@@RAB_PACK@@'); $e=[Array]::IndexOf($L,'#@@RAB_PACK_END@@'); if ($b -lt 0 -or $p -le $b -or $e -le $p) { throw 'this file is damaged or truncated - download RAB-Update.cmd again' }; $body=($L[($b+1)..($p-1)] -join ([char]13+[char]10)); [IO.File]::WriteAllText($env:RAB_TMP,$body,(New-Object Text.UTF8Encoding($false))); $s=($L[($p+1)..($e-1)] -join ''); [IO.File]::WriteAllBytes($env:RAB_PACK,[Convert]::FromBase64String($s)) } catch { Write-Host ('  FAILED: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%RAB_TMP%"
set "RAB_CODE=%ERRORLEVEL%"
if exist "%RAB_TMP%" del "%RAB_TMP%" >nul 2>&1
if exist "%RAB_PACK%" del "%RAB_PACK%" >nul 2>&1
echo.
if not "%RAB_CODE%"=="0" echo   Stopped with an error - the reason is above.
echo.
pause
exit /b %RAB_CODE%
:fail
echo.
pause
exit /b 1
#@@RAB_PS_BODY@@
# RAB Addon Updater (logic)
#
# Installs the newest RAB Scoreboard build into every Minecraft data folder
# this PC uses, then keeps existing worlds bound to it so nothing has to be
# re-activated in Edit World.
#
# Normally you do not run this file directly - double-click RAB-Update.cmd,
# which carries this script inside itself. You can also drag a .mcpack (or a
# folder that contains one) onto that .cmd.
#
# Options (for manual runs):
#   -PackPath <file|folder>   use this .mcpack instead of searching
#   -RunDir   <folder>        folder the .cmd lives in (set automatically)
#   -DataRoot <folder>        force one specific ...\com.mojang folder
#   -Force                    continue even if Minecraft is running
#
# The .cmd hands the dragged file / the embedded pack over through the
# RAB_PACK_ARG and RAB_RUN_DIR environment variables, so no path ever has to
# survive batch quoting (a trailing backslash used to break that).

param(
  [string]$PackPath,
  [string]$RunDir,
  [string]$DataRoot,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $PackPath -and $env:RAB_PACK_ARG) { $PackPath = $env:RAB_PACK_ARG }
if (-not $RunDir -and $env:RAB_RUN_DIR) { $RunDir = $env:RAB_RUN_DIR }

# a dragged folder arrives as C:\some\folder\ - drop the trailing slash
if ($PackPath) { $PackPath = $PackPath.TrimEnd("\") }
if ($RunDir) { $RunDir = $RunDir.TrimEnd("\") }

$packUuids  = @("efb65a54-925f-4010-81df-94f716666141", "f293a3f3-67f8-44ba-ac2f-faa727532237")
$packFolder = "RAB-Scoreboard"
$packUrl    = "https://sherowhayden-maker.github.io/addons/RAB-Scoreboard.mcpack"
$tempWork   = New-Object System.Collections.Generic.List[string]

function Say([string]$text) { Write-Host $text }

function Clear-Temp {
  foreach ($p in $tempWork) {
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
  }
  $tempWork.Clear()
}

function Stop-Fail([string]$text) {
  Write-Host ("  FAILED: " + $text)
  Clear-Temp
  exit 1
}

function Expand-PackFile([string]$file) {
  $work = Join-Path $env:TEMP ("rab-x-" + [IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  # Expand-Archive refuses anything that is not *.zip, and a pack is *.mcpack,
  # so unzip through .NET instead - it only cares about the bytes.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($file, $work)
  } catch {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    throw ((Split-Path $file -Leaf) + " is not a Minecraft pack - a .mcpack or .zip was expected")
  }
  if (Test-Path (Join-Path $work "manifest.json")) { return $work }
  $inner = Get-ChildItem $work -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "manifest.json") } |
    Select-Object -First 1
  if ($inner) { return $inner.FullName }
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  throw ((Split-Path $file -Leaf) + " is not a Minecraft pack - no manifest.json at its root")
}

# ---------------------------------------------------------------- 1. Minecraft
Say "  [1/5] Checking Minecraft"
if ($Force) {
  Say "        skipped (-Force)"
} else {
  if (Get-Process -Name "Minecraft.Windows" -ErrorAction SilentlyContinue) {
    Say "        Minecraft is open - close it completely, it locks the pack files."
    Say "        Waiting up to 60s for it to close..."
    $waited = 0
    while ($waited -lt 60 -and (Get-Process -Name "Minecraft.Windows" -ErrorAction SilentlyContinue)) {
      Start-Sleep -Seconds 1
      $waited++
      if ($waited % 10 -eq 0) { Say ("        still open (" + $waited + "s)") }
    }
    if (Get-Process -Name "Minecraft.Windows" -ErrorAction SilentlyContinue) {
      Stop-Fail "Minecraft is still open. Close it, then run this again."
    }
    Say "        Minecraft closed - continuing."
  } else {
    Say "        closed"
  }
}

# ------------------------------------------------------------ 2. Data folders
Say "  [2/5] Looking for Minecraft data folders"
$known = @()
if ($DataRoot) { $known += $DataRoot }
$pkgRoot = Join-Path $env:LocalAppData "Packages"
$known += @(
  (Join-Path $pkgRoot "Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang"),
  (Join-Path $pkgRoot "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe\LocalState\games\com.mojang"),
  (Join-Path $env:LocalAppData "games\com.mojang")
)
if (Test-Path $pkgRoot) {
  foreach ($pkg in (Get-ChildItem $pkgRoot -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "Microsoft.Minecraft*" })) {
    $known += (Join-Path $pkg.FullName "LocalState\games\com.mojang")
  }
}
$launcher = Join-Path $env:AppData "Minecraft Bedrock\Users"
if (Test-Path $launcher) {
  foreach ($u in (Get-ChildItem $launcher -Directory -ErrorAction SilentlyContinue)) {
    $known += (Join-Path $u.FullName "games\com.mojang")
  }
}

$roots = @()
foreach ($c in $known) {
  if ($c -and (Test-Path $c) -and ($roots -notcontains $c)) { $roots += $c }
}
if ($roots.Count -eq 0) { Stop-Fail "no Minecraft data folder found - is Bedrock installed on this PC?" }
foreach ($r in $roots) { Say ("        " + $r) }

# -------------------------------------------------------------- 3. The build
Say "  [3/5] Choosing the build to install"
$dirs = @()
foreach ($d in @($RunDir, $PSScriptRoot, (Get-Location).Path)) {
  if ($d -and (Test-Path $d)) { $dirs += (Resolve-Path $d).Path }
}
$dirs = @($dirs | Select-Object -Unique)

$packCandidates = @()
if ($PackPath) {
  if (Test-Path $PackPath -PathType Container) {
    $packCandidates += (Join-Path $PackPath "RAB-Scoreboard.mcpack")
    $packCandidates += @(Get-ChildItem $PackPath -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Extension -in @(".mcpack", ".zip") } |
                         ForEach-Object { $_.FullName })
  } else {
    $packCandidates += $PackPath
  }
}
foreach ($d in $dirs) {
  $packCandidates += @(
    (Join-Path $d "RAB-Scoreboard.mcpack"),
    (Join-Path $d "RAB-Scoreboard.zip"),
    (Join-Path $d "addons\RAB-Scoreboard.mcpack")
  )
  $parent = Split-Path $d -Parent
  if ($parent) { $packCandidates += (Join-Path $parent "addons\RAB-Scoreboard.mcpack") }
}

$packFile = $null
foreach ($c in $packCandidates) {
  if ($c -and (Test-Path $c -PathType Leaf)) { $packFile = (Resolve-Path $c).Path; break }
}

$builtFrom = $null
if (-not $packFile) {
  $srcDirs = @()
  foreach ($d in $dirs) {
    $srcDirs += (Join-Path $d "addons\rab-scoreboard")
    $srcDirs += (Join-Path $d "rab-scoreboard")
  }
  foreach ($s in @($srcDirs | Select-Object -Unique)) {
    if ($s -and (Test-Path (Join-Path $s "manifest.json"))) { $builtFrom = $s; break }
  }
  if ($builtFrom) {
    $zip = Join-Path $env:TEMP ("rab-build-" + [IO.Path]::GetRandomFileName() + ".zip")
    Compress-Archive -Path (Join-Path $builtFrom "*") -DestinationPath $zip -CompressionLevel Optimal
    $tempWork.Add($zip)
    $packFile = $zip
  }
}

if ($packFile) {
  $label = if ($builtFrom) { "built from " + $builtFrom } else { $packFile }
} else {
  $label = $packUrl
}

$work = $null
try {
  if ($packFile) {
    $work = Expand-PackFile $packFile
  } else {
    Say "        no local pack found - downloading from GitHub"
    $zip = Join-Path $env:TEMP ("rab-dl-" + [IO.Path]::GetRandomFileName() + ".zip")
    try {
      Invoke-WebRequest -Uri $packUrl -OutFile $zip -UseBasicParsing
    } catch {
      throw ("could not download the pack (" + $_.Exception.Message + ")")
    }
    $tempWork.Add($zip)
    $work = Expand-PackFile $zip
  }
} catch {
  Stop-Fail $_.Exception.Message
}
$tempWork.Add($work)

$manifest = Get-Content (Join-Path $work "manifest.json") -Raw | ConvertFrom-Json
if (-not $manifest.header -or -not $manifest.header.uuid) {
  Stop-Fail "the manifest.json in that build is not readable"
}
if ($packUuids -notcontains $manifest.header.uuid) {
  Stop-Fail ("that build is a different pack (uuid " + $manifest.header.uuid + "), not RAB Scoreboard")
}
$version = @($manifest.header.version)
$versionText = ($version -join ".")
Say ("        " + $manifest.header.name + "  (build " + $versionText + ")")
Say ("        " + $label)

# --------------------------------------------------------------- 4. Install
Say "  [4/5] Installing"
$installInto = @()
foreach ($r in $roots) {
  $hadOld = $false
  foreach ($kind in @("behavior_packs", "development_behavior_packs")) {
    $dir = Join-Path $r $kind
    if (-not (Test-Path $dir)) { continue }
    foreach ($packDir in (Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue)) {
      $mf = Join-Path $packDir.FullName "manifest.json"
      if (-not (Test-Path $mf)) { continue }
      try {
        $old = Get-Content $mf -Raw | ConvertFrom-Json
        if ($packUuids -contains $old.header.uuid) {
          Remove-Item $packDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
          if (Test-Path $packDir.FullName) {
            Say ("        could not remove " + $kind + "\" + $packDir.Name + " (in use)")
          } else {
            Say ("        removed " + $kind + "\" + $packDir.Name + "  (v" + ($old.header.version -join ".") + ")")
          }
          $hadOld = $true
        }
      } catch { }
    }
  }
  if ($hadOld) { $installInto += $r }
}

if ($installInto.Count -eq 0) {
  $shared = $roots | Where-Object { $_ -like "*\Shared\*" } | Select-Object -First 1
  if ($shared) {
    $installInto = @($shared)
  } else {
    $withWorlds = @()
    foreach ($r in $roots) {
      $w = Join-Path $r "minecraftWorlds"
      if ((Test-Path $w) -and (@(Get-ChildItem $w -Directory -ErrorAction SilentlyContinue).Count -gt 0)) {
        $withWorlds += $r
      }
    }
    if ($withWorlds.Count -gt 0) { $installInto = @($withWorlds[0]) } else { $installInto = @($roots[0]) }
  }
  Say "        no old copy found - fresh install"
}

foreach ($t in $installInto) {
  $bp = Join-Path $t "behavior_packs"
  $dest = Join-Path $bp $packFolder
  New-Item -ItemType Directory -Force -Path $bp | Out-Null
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  try {
    Copy-Item (Join-Path $work "*") $dest -Recurse -Force
  } catch {
    Stop-Fail ("could not write " + $dest + " (" + $_.Exception.Message + ")")
  }
  if (-not (Test-Path (Join-Path $dest "manifest.json"))) {
    Stop-Fail ("install did not complete in " + $dest)
  }
  $icon = if (Test-Path (Join-Path $dest "pack_icon.png")) { "yes" } else { "no" }
  Say ("        installed -> " + $dest)
  Say ("                     (icon: " + $icon + ")")
}

# ------------------------------------------------------------ 5. Re-bind worlds
Say "  [5/5] Re-binding worlds"
$updated = 0
$current = 0
$cleared = 0

foreach ($r in $roots) {
  $worlds = Join-Path $r "minecraftWorlds"
  if (-not (Test-Path $worlds)) { continue }
  foreach ($w in (Get-ChildItem $worlds -Directory -ErrorAction SilentlyContinue)) {
    $name = "(unnamed)"
    $lf = Join-Path $w.FullName "levelname.txt"
    if (Test-Path $lf) {
      $name = ((Get-Content $lf -Raw) -replace "\r?\n", "").Trim()
      if (-not $name) { $name = "(unnamed)" }
    }

    # a copy stored inside the world folder shadows the installed one
    $emb = Join-Path $w.FullName "behavior_packs"
    if (Test-Path $emb) {
      foreach ($inner in (Get-ChildItem $emb -Directory -ErrorAction SilentlyContinue)) {
        $mf = Join-Path $inner.FullName "manifest.json"
        if (-not (Test-Path $mf)) { continue }
        try {
          $j = Get-Content $mf -Raw | ConvertFrom-Json
          if ($packUuids -contains $j.header.uuid) {
            Remove-Item $inner.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Say ("        cleared old copy embedded in world '" + $name + "'")
            $cleared++
          }
        } catch { }
      }
    }

    $wbp = Join-Path $w.FullName "world_behavior_packs.json"
    if (-not (Test-Path $wbp)) { continue }
    try {
      $parsed = Get-Content $wbp -Raw | ConvertFrom-Json
    } catch {
      Say ("        could not read " + $wbp)
      continue
    }
    # ConvertFrom-Json hands back the array as a single object, so copy the
    # elements out by hand - otherwise the entries below are one big array.
    $entries = @()
    foreach ($x in $parsed) { $entries += $x }

    $changed = $false
    $already = $false
    foreach ($e in $entries) {
      if ($packUuids -contains $e.pack_id) {
        if (($e.version -join ".") -eq $versionText) { $already = $true }
        else { $e.version = $version; $changed = $true }
      }
    }

    if ($changed) {
      Copy-Item $wbp ($wbp + ".bak") -Force -ErrorAction SilentlyContinue
      $json = ConvertTo-Json -InputObject @($entries) -Depth 5
      [IO.File]::WriteAllText($wbp, $json, (New-Object System.Text.UTF8Encoding($false)))
      Say ("        updated world '" + $name + "' -> v" + $versionText)
      $updated++
    } elseif ($already) {
      $current++
    }
  }
}

if ($updated -eq 0 -and $current -eq 0 -and $cleared -eq 0) {
  Say "        no world uses the pack yet - nothing to re-bind"
} elseif ($updated -eq 0 -and $current -gt 0) {
  Say "        every world is already on v$versionText"
}

# ------------------------------------------------------------------ summary
Say ""
Say ("  DONE - RAB Scoreboard v" + $versionText)
Say ("    build   : " + $label)
foreach ($t in $installInto) { Say ("    install : " + (Join-Path $t ("behavior_packs\" + $packFolder))) }
$worldLine = "$updated updated, $current already current"
if ($cleared -gt 0) { $worldLine += ", $cleared embedded copy cleared" }
Say ("    worlds  : " + $worldLine)
Say ""
Say "  Open Minecraft and play - the pack stays enabled in your worlds."

Clear-Temp
exit 0
#@@RAB_PACK@@
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
#@@RAB_PACK_END@@
