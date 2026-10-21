@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.19.0 inside
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
