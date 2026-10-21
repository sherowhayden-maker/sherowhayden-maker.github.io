@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.20.0 inside
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
