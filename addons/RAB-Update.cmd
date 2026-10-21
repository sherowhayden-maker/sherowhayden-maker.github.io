@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.10.0 inside
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
