@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 3.3.6 inside
echo   it. Double-click and it installs that build into every
echo   Minecraft data folder on this PC, then keeps your worlds
echo   bound to it. No download, nothing else to copy.
echo.
echo   Drag a .mcpack onto this file to install a different build.
echo.
echo   Not sure what is installed, or the realm looks unchanged?
echo   Run this file as:  RAB-Update.cmd /report
echo   It changes nothing and prints the build in every folder, the
echo   build each world is bound to, and the Realm re-apply steps.
echo ================================================================
echo.
set "RAB_SELF=%~f0"
set "RAB_RUN_DIR=%~dp0"
set "RAB_REPORT="
if /i "%~1"=="/report" set "RAB_REPORT=-Report"
if /i "%~1"=="-report" set "RAB_REPORT=-Report"
if /i "%~1"=="report" set "RAB_REPORT=-Report"
set "RAB_PACK_ARG=%~1"
if defined RAB_REPORT set "RAB_PACK_ARG="
set "RAB_TMP=%TEMP%\rab-update-run.ps1"
set "RAB_PACK=%TEMP%\rab-update-pack.mcpack"
if not defined RAB_PACK_ARG set "RAB_PACK_ARG=%RAB_PACK%"
if exist "%RAB_TMP%" del "%RAB_TMP%" >nul 2>&1
if exist "%RAB_PACK%" del "%RAB_PACK%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $L=Get-Content -LiteralPath $env:RAB_SELF; $b=[Array]::IndexOf($L,'#@@RAB_PS_BODY@@'); $p=[Array]::IndexOf($L,'#@@RAB_PACK@@'); $e=[Array]::IndexOf($L,'#@@RAB_PACK_END@@'); if ($b -lt 0 -or $p -le $b -or $e -le $p) { throw 'this file is damaged or truncated - download RAB-Update.cmd again' }; $body=($L[($b+1)..($p-1)] -join ([char]13+[char]10)); [IO.File]::WriteAllText($env:RAB_TMP,$body,(New-Object Text.UTF8Encoding($false))); $s=($L[($p+1)..($e-1)] -join ''); [IO.File]::WriteAllBytes($env:RAB_PACK,[Convert]::FromBase64String($s)) } catch { Write-Host ('  FAILED: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%RAB_TMP%" %RAB_REPORT%
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
  [switch]$Force,
  [switch]$Report
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
if ($Report) {
  Say "        skipped (report only - nothing is changed)"
} elseif ($Force) {
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

# ------------------------------------------------------------- report mode
# Reads and reports. No install, no re-bind, no deletes: the answer to "which
# build is the realm actually running, and why does nothing I do show up?"
if ($Report) {
  Say ""
  Say "  RAB REPORT - what is on this PC, and what each world is bound to"
  Say "  (nothing is changed by this mode)"
  Say ""

  function Get-PackVersion([string]$file) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($file)
    try {
      $entry = $zip.Entries | Where-Object { $_.FullName -eq "manifest.json" } | Select-Object -First 1
      if (-not $entry) { return $null }
      $reader = New-Object IO.StreamReader($entry.Open())
      try { $m = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Close() }
      return ($m.header.version -join ".")
    } finally { $zip.Dispose() }
  }

  $carried = $null
  if ($PackPath -and (Test-Path $PackPath -PathType Leaf)) {
    try { $carried = Get-PackVersion $PackPath } catch { $carried = $null }
  }
  Say ("  Build this file carries: " + $(if ($carried) { "v" + $carried } else { "unknown" }))
  Say ""

  $installed = @()
  foreach ($r in $roots) {
    foreach ($kind in @("behavior_packs", "development_behavior_packs")) {
      $dir = Join-Path $r $kind
      if (-not (Test-Path $dir)) { continue }
      foreach ($packDir in (Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue)) {
        $mf = Join-Path $packDir.FullName "manifest.json"
        if (-not (Test-Path $mf)) { continue }
        try {
          $j = Get-Content $mf -Raw | ConvertFrom-Json
          if ($packUuids -contains $j.header.uuid) {
            $installed += [pscustomobject]@{ Ver = ($j.header.version -join "."); Path = $packDir.FullName }
          }
        } catch { }
      }
    }
  }
  Say "  Installed copies of the pack on disk:"
  if ($installed.Count -eq 0) { Say "    none - the pack is not installed on this PC at all" }
  foreach ($p in $installed) { Say ("    v" + $p.Ver + "   " + $p.Path) }
  Say ""

  $bound = 0
  $stale = @()
  Say "  Worlds and the build each is bound to:"
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
      $wbp = Join-Path $w.FullName "world_behavior_packs.json"
      if (Test-Path $wbp) {
        try {
          $arr = Get-Content $wbp -Raw | ConvertFrom-Json
          foreach ($e in @($arr)) {
            if ($packUuids -notcontains $e.pack_id) { continue }
            $v = ($e.version -join ".")
            $bound++
            Say ("    " + $name + "  ->  bound to v" + $v)
            if ($carried -and $v -ne $carried) { $stale += $name }
          }
        } catch { Say ("    " + $name + "  ->  world_behavior_packs.json is unreadable") }
      }
      $emb = Join-Path $w.FullName "behavior_packs"
      if (Test-Path $emb) {
        foreach ($inner in (Get-ChildItem $emb -Directory -ErrorAction SilentlyContinue)) {
          $mf = Join-Path $inner.FullName "manifest.json"
          if (-not (Test-Path $mf)) { continue }
          try {
            $j = Get-Content $mf -Raw | ConvertFrom-Json
            if ($packUuids -contains $j.header.uuid) {
              Say ("    " + $name + "  ->  EMBEDDED copy v" + ($j.header.version -join ".") + "  (this one wins over the installed copy)")
              if ($carried -and ($j.header.version -join ".") -ne $carried) { $stale += $name }
            }
          } catch { }
        }
      }
    }
  }
  if ($bound -eq 0) { Say "    no world on this PC has the pack applied" }
  Say ""

  Say "  What this means:"
  if ($stale.Count -gt 0) {
    Say ("    " + ($stale -join ", ") + "  is/are on an older build than this file carries.")
    Say "    Run this file again WITHOUT /report to install and re-bind them."
  } elseif ($carried -and $bound -gt 0) {
    Say "    Every world here is bound to the build this file carries (v" + $carried + ")."
    Say "    If the world is a REALM, that is not enough - see the note below."
  }
  Say ""
  Say "  A REALM is a different story, and this is the usual reason a fix"
  Say "  does not show up in game:"
  Say "    the realm keeps its own copy of the pack on Microsoft's servers."
  Say "    Installing on this PC only makes the new build AVAILABLE. The"
  Say "    realm keeps running the build it was saved with until the realm"
  Say "    owner re-applies it:"
  Say "      Realm settings (the gear) -> World settings (the pencil) ->"
  Say "      Behavior packs -> untick RAB Scoreboard -> tick it again -> Save"
  Say "    Then close the realm with the back arrow (that uploads it) and"
  Say "    reopen it. Only the realm's owner account can do this."
  Say ""
  Say "  To confirm which build is really running, join and open the RAB"
  Say "  Manager (echo shard): the bottom line of the menu reads the build,"
  Say "  and the chat prints it on your first spawn."
  Say ""
  Clear-Temp
  exit 0
}

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
