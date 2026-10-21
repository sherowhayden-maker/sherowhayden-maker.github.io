@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.12.0 inside
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
