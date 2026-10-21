@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.16.2 inside
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
