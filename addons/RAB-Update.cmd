@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 3.0.1 inside
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
