@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.8.1 inside
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
