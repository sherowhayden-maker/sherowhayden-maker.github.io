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
