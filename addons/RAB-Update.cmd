@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.17.1 inside
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
