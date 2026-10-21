@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.14.0 inside
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
