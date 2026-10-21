@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.17.2 inside
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
