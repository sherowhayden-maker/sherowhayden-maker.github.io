@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.20.1 inside
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
