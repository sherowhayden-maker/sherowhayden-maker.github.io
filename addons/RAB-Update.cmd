@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.7.5 inside
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
