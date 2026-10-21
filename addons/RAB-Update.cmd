@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.18.0 inside
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
