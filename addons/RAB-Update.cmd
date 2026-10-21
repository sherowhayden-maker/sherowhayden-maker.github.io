@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.13.0 inside
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
