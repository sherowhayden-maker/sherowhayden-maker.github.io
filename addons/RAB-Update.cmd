@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.16.0 inside
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
