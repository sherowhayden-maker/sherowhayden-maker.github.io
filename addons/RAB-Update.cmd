@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 3.0.0 inside
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
