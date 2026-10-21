@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.11.0 inside
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
