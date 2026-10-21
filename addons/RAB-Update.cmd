@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.17.0 inside
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
