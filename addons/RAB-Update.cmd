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
