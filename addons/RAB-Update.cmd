@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.15.0 inside
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
