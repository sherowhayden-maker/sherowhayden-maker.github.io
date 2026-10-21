@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.16.1 inside
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
