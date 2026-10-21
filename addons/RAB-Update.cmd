@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 3.1.0 inside
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
