@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 3.1.3 inside
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
