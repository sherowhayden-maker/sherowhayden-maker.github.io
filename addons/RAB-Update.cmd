@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.9.0 inside
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
