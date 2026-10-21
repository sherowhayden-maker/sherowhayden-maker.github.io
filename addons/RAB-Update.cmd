@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.8.2 inside
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
