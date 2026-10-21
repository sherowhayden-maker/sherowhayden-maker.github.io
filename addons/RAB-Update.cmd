@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.15.1 inside
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
