@echo off
setlocal
title RAB Personal HUD - installer
echo.
set "RAB_SELF=%~f0"
set "RAB_TMP=%TEMP%\rab-hud-run.ps1"
set "RAB_PACK=%TEMP%\rab-hud-pack.mcpack"
set "RAB_HUD_PACK=%RAB_PACK%"
if exist "%RAB_TMP%" del "%RAB_TMP%" >nul 2>&1
if exist "%RAB_PACK%" del "%RAB_PACK%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $L=Get-Content -LiteralPath $env:RAB_SELF; $b=[Array]::IndexOf($L,'#@@RAB_HUD_BODY@@'); $p=[Array]::IndexOf($L,'#@@RAB_HUD_PACK@@'); $e=[Array]::IndexOf($L,'#@@RAB_HUD_PACK_END@@'); if ($b -lt 0 -or $p -le $b -or $e -le $p) { throw 'this file is damaged or truncated - download RAB-HUD-Install.cmd again' }; $body=($L[($b+1)..($p-1)] -join ([char]13+[char]10)); [IO.File]::WriteAllText($env:RAB_TMP,$body,(New-Object Text.UTF8Encoding($false))); $s=($L[($p+1)..($e-1)] -join ''); [IO.File]::WriteAllBytes($env:RAB_PACK,[Convert]::FromBase64String($s)) } catch { Write-Host ('  FAILED: ' + $_.Exception.Message); exit 1 }"
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
#@@RAB_HUD_BODY@@
# RAB HUD installer (logic)
#
# Installs ONE thing: the optional RAB Personal HUD resource pack, the one that
# moves the per-player line from above the hotbar to the bottom-right corner.
# It touches nothing else - no scoreboard files, no world behaviour packs - so
# it is safe to run even if the scoreboard is already up to date.
#
# Normally you do not run this file directly: double-click RAB-HUD-Install.cmd,
# which carries both this script and the pack inside itself.
#
# Why this exists: a .mcpack is a ZIP. On a PC with WinRAR installed, a .mcpack
# with no association opens in WinRAR instead of importing into Minecraft, and
# the pack never appears in the world's Resource Packs list. This file unpacks
# the pack programmatically, so no file association can get in the way.

param(
  [string]$PackPath,
  [string]$DataRoot,
  [switch]$Force,
  [switch]$NoUpdateCheck
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $PackPath -and $env:RAB_HUD_PACK) { $PackPath = $env:RAB_HUD_PACK }

$hudUuids    = @("04be9756-7719-46a7-9829-7af232c88ef3")
$hudFolder   = "RAB-Personal-HUD"
$scoreUuids  = @("efb65a54-925f-4010-81df-94f716666141", "f293a3f3-67f8-44ba-ac2f-faa727532237")

function Say([string]$t) { Write-Host $t }
function Stop-Fail([string]$t) { Write-Host ("  FAILED: " + $t); exit 1 }

function Get-MinecraftClient {
  @(Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "*Minecraft*" -and $_.ProcessName -notlike "*Server*" })
}

Say "================================================================"
Say "  RAB Personal HUD - installer"
Say "  Moves your own per-player line to the bottom-right corner."
Say "================================================================"
Say ""

# ---------------------------------------------------------- 1. game must be shut
Say "  [1/4] Checking Minecraft"
if ($Force) {
  Say "        skipped (-Force)"
} elseif (@(Get-MinecraftClient).Count -gt 0) {
  Say "        Minecraft is open - close it completely, it locks the pack files"
  Say "        and rewrites the world's pack list when it exits."
  $waited = 0
  while ($waited -lt 60 -and @(Get-MinecraftClient).Count -gt 0) {
    Start-Sleep -Seconds 1
    $waited++
    if ($waited % 10 -eq 0) { Say ("        still open (" + $waited + "s)") }
  }
  if (@(Get-MinecraftClient).Count -gt 0) { Stop-Fail "Minecraft is still open. Close it, then run this again." }
  Say "        closed"
} else {
  Say "        closed"
}

# ------------------------------------------------------------ 2. data folders
Say "  [2/4] Looking for Minecraft data folders"
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

# The same folder turns up twice on some PCs: once from the Packages scan (short
# 8.3 path) and once from the known list (long path). Installing twice is
# harmless but "2 worlds skipped" for 1 world is not, so de-duplicate on the
# trailing path segments instead of the raw string.
function Get-RootKey([string]$p) {
  $parts = @($p -split '\\' | Where-Object { $_ })
  $take = [Math]::Min(4, $parts.Count)
  return (($parts[($parts.Count - $take)..($parts.Count - 1)]) -join '\').ToLower()
}

$roots = @()
$seenRoots = @{}
foreach ($c in $known) {
  if (-not $c -or -not (Test-Path $c)) { continue }
  $key = Get-RootKey $c
  if ($seenRoots.ContainsKey($key)) { continue }
  $seenRoots[$key] = $true
  $roots += $c
}
if ($roots.Count -eq 0) {
  Stop-Fail "no Minecraft data folder found - is Bedrock installed for this Windows account?"
}
foreach ($r in $roots) { Say ("        " + $r) }

# ---------------------------------------------------------------- 3. install
Say "  [3/4] Installing the pack"
if (-not $PackPath -or -not (Test-Path $PackPath -PathType Leaf)) {
  Stop-Fail "the pack did not come out of this file - download RAB-HUD-Install.cmd again"
}

$work = Join-Path $env:TEMP ("rab-hud-x-" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($PackPath, $work)
  } catch {
    Stop-Fail "the built-in pack is not a readable .mcpack"
  }
  if (-not (Test-Path (Join-Path $work "manifest.json"))) {
    Stop-Fail "the built-in pack has no manifest.json at its root"
  }
  $manifest = Get-Content (Join-Path $work "manifest.json") -Raw | ConvertFrom-Json
  if (-not $manifest.header -or ($hudUuids -notcontains $manifest.header.uuid)) {
    Stop-Fail "the built-in pack is not RAB Personal HUD"
  }
  $version = @($manifest.header.version)
  $versionText = ($version -join ".")
  Say ("        " + $manifest.header.name + "  (build " + $versionText + ")")

  foreach ($r in $roots) {
    $rp = Join-Path $r "resource_packs"
    New-Item -ItemType Directory -Force -Path $rp | Out-Null
    foreach ($packDir in (Get-ChildItem $rp -Directory -ErrorAction SilentlyContinue)) {
      $mf = Join-Path $packDir.FullName "manifest.json"
      if (-not (Test-Path $mf)) { continue }
      try {
        $old = Get-Content $mf -Raw | ConvertFrom-Json
        if ($hudUuids -contains $old.header.uuid) {
          Remove-Item $packDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
      } catch { }
    }
    $dest = Join-Path $rp $hudFolder
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    try {
      Copy-Item (Join-Path $work "*") $dest -Recurse -Force
    } catch {
      Stop-Fail ("could not write " + $dest + " (" + $_.Exception.Message + ")")
    }
    if (-not (Test-Path (Join-Path $dest "manifest.json"))) {
      Stop-Fail ("install did not complete in " + $dest)
    }
    Say ("        installed -> " + $dest)
  }
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

# -------------------------------------------------------------- 4. world binding
Say "  [4/4] Applying it to your worlds"
$applied = 0
$already = 0
$skipped = 0
$appliedNames = @()
$alreadyNames = @()
$skippedNames = @()
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

    # Only worlds that already run the RAB scoreboard: the HUD pack exists to
    # serve that line, and forcing it on an unrelated world would move that
    # world's action bar behind its owner's back.
    $usesScoreboard = $false
    $wbp = Join-Path $w.FullName "world_behavior_packs.json"
    if (Test-Path $wbp) {
      try {
        foreach ($e in (Get-Content $wbp -Raw | ConvertFrom-Json)) {
          if ($scoreUuids -contains $e.pack_id) { $usesScoreboard = $true }
        }
      } catch { }
    }
    if (-not $usesScoreboard) { $skipped++; $skippedNames += $name; continue }

    $wrp = Join-Path $w.FullName "world_resource_packs.json"
    $entries = @()
    if (Test-Path $wrp) {
      try {
        foreach ($x in (Get-Content $wrp -Raw | ConvertFrom-Json)) { $entries += $x }
      } catch {
        Say ("        could not read " + $wrp)
        continue
      }
    }
    $changed = $false
    $found = $false
    # The old version is worth naming: "applied" reads like a first-time install
    # even when all that happened was 1.1.0 -> 1.2.0, which is the usual case and
    # used to look like the installer had done nothing at all.
    $oldVersionText = ""
    foreach ($e in $entries) {
      if ($hudUuids -contains $e.pack_id) {
        $found = $true
        $seen = (@($e.version) -join ".")
        if ($seen -ne $versionText) { $oldVersionText = $seen; $e.version = $version; $changed = $true }
      }
    }
    if (-not $found) {
      $entries += [pscustomobject]@{ pack_id = $hudUuids[0]; version = $version }
      $changed = $true
    }
    if ($changed) {
      if (Test-Path $wrp) { Copy-Item $wrp ($wrp + ".bak") -Force -ErrorAction SilentlyContinue }
      $json = ConvertTo-Json -InputObject @($entries) -Depth 5
      [IO.File]::WriteAllText($wrp, $json, (New-Object System.Text.UTF8Encoding($false)))
      if ($oldVersionText) {
        Say ("        upgraded world '" + $name + "'  v" + $oldVersionText + " -> v" + $versionText)
      } else {
        Say ("        added to world '" + $name + "'")
      }
      $applied++
      $appliedNames += $name
    } else {
      Say ("        '" + $name + "' already has it")
      $already++
      $alreadyNames += $name
    }
  }
}

# ---------------------------------------------------------------- 5. verdict
# "The pack is not in the world's Resource Packs list" is the one report this
# installer cannot fix blind: the file is on disk, the world references it, and
# the game still does not list it. Everything that can be checked locally is
# printed here so the next screenshot names the folder, the pack and the world
# instead of describing them.
Say "  [5/5] Checking what Minecraft will see"
$issues = @()
foreach ($r in $roots) {
  $rp = Join-Path $r "resource_packs"
  $dest = Join-Path $rp $hudFolder
  $mf = Join-Path $dest "manifest.json"
  $state = "missing"
  $packVersion = ""
  if (Test-Path $mf) {
    try {
      $pm = Get-Content $mf -Raw | ConvertFrom-Json
      if ($hudUuids -contains $pm.header.uuid) {
        $packVersion = (@($pm.header.version) -join ".")
        $state = "ok v" + $packVersion
      } else {
        $state = "wrong pack"
        $issues += ($dest + " holds a manifest that is not RAB Personal HUD")
      }
    } catch {
      $state = "manifest does not parse"
      $issues += ($mf + " does not parse - Minecraft skips the folder silently")
    }
  } else {
    # Two other shapes of "on disk but invisible": a nested copy, and a stray
    # folder somewhere else in resource_packs that still carries our UUID.
    $nested = Join-Path $dest $hudFolder
    if (Test-Path (Join-Path $nested "manifest.json")) {
      $state = "nested one level too deep"
      $issues += ($dest + " contains another " + $hudFolder + " folder - the manifest must sit at the top")
    }
    $hits = @()
    if (Test-Path $rp) {
      foreach ($d in (Get-ChildItem $rp -Directory -ErrorAction SilentlyContinue)) {
        $m2 = Join-Path $d.FullName "manifest.json"
        if (-not (Test-Path $m2)) { continue }
        try {
          $m3 = Get-Content $m2 -Raw | ConvertFrom-Json
          if ($hudUuids -contains $m3.header.uuid) { $hits += $d.Name }
        } catch { }
      }
    }
    if ($hits.Count -gt 0) { $state = "in a differently named folder: " + ($hits -join ', ') }
  }

  $worldNames = @()
  $boundNames = @()
  $worlds = Join-Path $r "minecraftWorlds"
  if (Test-Path $worlds) {
    foreach ($w in (Get-ChildItem $worlds -Directory -ErrorAction SilentlyContinue)) {
      $n = "(unnamed)"
      $lf = Join-Path $w.FullName "levelname.txt"
      if (Test-Path $lf) { $n = ((Get-Content $lf -Raw) -replace "\r?\n", "").Trim() }
      if ($n) { $worldNames += $n }
      $wrp = Join-Path $w.FullName "world_resource_packs.json"
      if (Test-Path $wrp) {
        try {
          foreach ($e in (Get-Content $wrp -Raw | ConvertFrom-Json)) {
            # One world can list the pack twice (a stale entry and a fresh one);
            # naming it twice in the report just looks like two worlds.
            if (($hudUuids -contains $e.pack_id) -and ($boundNames -notcontains $n)) { $boundNames += $n }
          }
        } catch { }
      }
    }
  }

  Say ("        " + $r)
  Say ("          pack    : " + $state)
  Say ("          worlds  : " + $worldNames.Count)
  # Which folder holds which world is the whole question when the pack is on
  # disk but missing from the list, so name them - and lead with the worlds
  # that actually reference the pack, since a dozen unrelated worlds would
  # otherwise push them off the end of the line.
  if ($worldNames.Count -gt 0) {
    $preview = @($boundNames) + @($worldNames | Where-Object { $boundNames -notcontains $_ })
    $preview = @($preview | Select-Object -First 6)
    $more = ""
    if ($worldNames.Count -gt $preview.Count) { $more = " (+ " + ($worldNames.Count - $preview.Count) + " more)" }
    Say ("          names   : " + ($preview -join ' | ') + $more)
  }
  if ($boundNames.Count -gt 0) { Say ("          bound in: " + ($boundNames -join ', ')) }
  if ($state -ne "missing" -and $boundNames.Count -gt 0 -and $state -notlike "ok v*") {
    $issues += ("a world in " + $r + " wants the pack but the folder is not where Minecraft looks")
  }
}

# A .mcpack with no file association never imports: double-clicking it opens the
# ZIP tool instead, which is exactly how a correct pack looks "not installed".
# Reported as information, not as a fault - this installer does not need the
# association, it only matters if the player tries the double-click route.
$assocLines = @()
foreach ($ext in @(".mcpack", ".mcaddon")) {
  $line = ""
  try { $line = (cmd /c "assoc $ext 2>nul") } catch { }
  if (-not $line -or $line -match "No association") {
    $assocLines += ($ext + "  -> nothing (double-click does not import)")
  } elseif ($line -match "(?i)rar|7-?zip|winzip|izarc") {
    $assocLines += ($ext + "  -> " + ($line -replace '^[^=]+=', '') + " (opens an archive, does not import)")
  } else {
    $assocLines += ($ext + "  -> " + ($line -replace '^[^=]+=', '') + " (imports)")
  }
}

if ($issues.Count -gt 0) {
  Say ""
  Say "  What is wrong here:"
  foreach ($i in $issues) { Say ("    - " + $i) }
} else {
  Say ""
  Say "  On disk everything lines up: pack present in every folder, worlds reference it."
  Say "  If Minecraft still does not list it, the pack is what it is rejecting."
}
Say ""
Say "  Double-click import (the route that needs no installer):"
foreach ($l in $assocLines) { Say ("    " + $l) }

Say ""
if ($applied -eq 0 -and $already -eq 0 -and $skipped -eq 0) {
  Say "  No worlds found on this PC yet - open the world once, then run this again."
}
# "0 applied" is not a failure: a world that already carries the pack needs no
# change, and saying only "0" made a correct run read like a broken one.
Say ("  DONE - RAB Personal HUD v" + $versionText)
Say ("    installed into : " + $roots.Count + " Minecraft folder(s)")
if ($applied -gt 0) {
  Say ("    applied to     : " + $applied + " world(s) - " + ($appliedNames -join ', '))
}
if ($already -gt 0) {
  Say ("    already had it : " + $already + " world(s) - " + ($alreadyNames -join ', '))
}
if ($skipped -gt 0) {
  # A bare count here read as "the installer skipped the worlds that matter".
  # The rule is narrow and deliberate, so name the worlds and state the rule.
  $shown = @($skippedNames | Select-Object -First 6)
  $more = if ($skippedNames.Count -gt $shown.Count) { " (+ " + ($skippedNames.Count - $shown.Count) + " more)" } else { "" }
  Say ("    left alone     : " + $skipped + " world(s) - no RAB scoreboard bound, so the")
  Say ("                     action bar there was not touched: " + ($shown -join ', ') + $more)
}
if ($applied -eq 0 -and $already -eq 0 -and $skipped -gt 0) {
  Say "    none of those worlds run the RAB scoreboard - this pack only serves its line."
  Say "    Install the scoreboard first (RAB-Update.cmd), then run this again."
}
# ---------------------------------------------- is this the newest build?
# This file is a snapshot: the pack inside it can never change, so re-running
# an old download reinstalls the old build forever and looks exactly like "the
# HUD still does not move". The version line alone does not help - nobody knows
# which build is current - so ask the site and say it plainly.
if (-not $NoUpdateCheck) {
  $live = $null
  $liveVersion = $null
  try {
    $hudUrl = "https://sherowhayden-maker.github.io/addons/RAB-HUD.mcpack"
    $tmpLive = Join-Path $env:TEMP ("rab-hud-live-" + [IO.Path]::GetRandomFileName() + ".mcpack")
    Invoke-WebRequest -Uri $hudUrl -UseBasicParsing -TimeoutSec 6 -OutFile $tmpLive
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $lz = [IO.Compression.ZipFile]::OpenRead($tmpLive)
    try {
      $lent = $lz.Entries | Where-Object { $_.FullName -eq "manifest.json" } | Select-Object -First 1
      if ($lent) {
        $lr = New-Object IO.StreamReader($lent.Open())
        try { $lm = $lr.ReadToEnd() | ConvertFrom-Json } finally { $lr.Close() }
        if ($hudUuids -contains $lm.header.uuid) {
          $liveVersion = @($lm.header.version)
          $live = ($liveVersion -join ".")
        }
      }
    } finally { $lz.Dispose() }
    Remove-Item $tmpLive -Force -ErrorAction SilentlyContinue
  } catch { $live = $null }

  # Only "the site is newer" is worth warning about. A publish that has not
  # landed yet leaves the site behind, which is not the player's problem.
  $siteIsNewer = $false
  if ($live) {
    $n = [Math]::Max(@($version).Count, @($liveVersion).Count)
    for ($i = 0; $i -lt $n; $i++) {
      $a = if ($i -lt @($version).Count) { [int]@($version)[$i] } else { 0 }
      $b = if ($i -lt @($liveVersion).Count) { [int]@($liveVersion)[$i] } else { 0 }
      if ($a -ne $b) { $siteIsNewer = ($b -gt $a); break }
    }
  }

  if ($siteIsNewer) {
    Say ""
    Say  "  ==============================================================="
    Say ("   OUT OF DATE: this file carries v" + $versionText + ", the site has v" + $live + ".")
    Say ("   Re-running this copy installs v" + $versionText + " every time.")
    Say  "  ==============================================================="
    # "Download it again" is a manual step, and a browser that silently refuses a
    # .cmd (SmartScreen, a stale cached copy, the file landing under a new name)
    # leaves the old build in Downloads looking untouched - which reads as "the
    # fix did not work". So fetch the current build ourselves and offer to run it.
    # RAB_HUD_SELFUPDATED guards against an endless chain of installers.
    if ($env:RAB_HUD_SELFUPDATED -ne "1") {
      $newCmd = Join-Path $env:TEMP ("RAB-HUD-Install-" + $live + ".cmd")
      $fetched = $false
      try {
        Invoke-WebRequest -Uri "https://sherowhayden-maker.github.io/addons/RAB-HUD-Install.cmd" -UseBasicParsing -TimeoutSec 20 -OutFile $newCmd
        $full = Get-Content $newCmd -Raw
        # A truncated download or an HTML error page must not be offered as an
        # installer. The real .cmd always carries this pack's UUID, so check for
        # that rather than for a marker (this script may not contain one - the
        # build refuses to embed a script that does).
        if ($full -and $full.Length -gt 5000 -and $full.Contains($hudUuids[0])) { $fetched = $true }
      } catch { $fetched = $false }

      if ($fetched) {
        $mb = [Math]::Round(((Get-Item $newCmd).Length / 1KB), 1)
        Say ("   Fetched the current build (v" + $live + ", " + $mb + " KB) to:")
        Say ("     " + $newCmd)
        Say ""
        Say "   Run it now? [Y/n]"
        $ans = ""
        try { $ans = Read-Host } catch { $ans = "" }
        if (-not $ans -or $ans -match "^(y|yes|)$") {
          $env:RAB_HUD_SELFUPDATED = "1"
          Say "   starting it - this window can be closed"
          Start-Process -FilePath "cmd.exe" -ArgumentList "/c", ("`"" + $newCmd + "`"")
          exit 0
        }
        Say ("   left it at " + $newCmd + " - double-click that when you are ready")
      } else {
        Say "   Could not fetch it automatically (offline, or a browser is blocking it)."
        Say "   Open this address in a browser and run what it downloads:"
        Say "     https://sherowhayden-maker.github.io/addons/RAB-HUD-Install.cmd"
      }
    }
  } elseif ($live) {
    Say ""
    Say ("  This is the newest build (v" + $live + ").")
  }
}

Say ""
Say "  Load the world and look at the BOTTOM-RIGHT corner:"
Say "      yourname - OWNER - Rank"
Say ""
Say "  Still centred above the hotbar? Then the world is not using the pack yet:"
Say "    local world -> Play -> pencil (Edit) -> Settings -> Resource Packs"
Say "                   -> Active -> add 'RAB Personal HUD'"
Say "    Realm       -> a Realm serves its OWN pack list; nothing installed on"
Say "                   this PC changes it. Either Settings -> Global Resources"
Say "                   -> activate 'RAB Personal HUD' (this device only), or"
Say "                   apply both packs to a local copy and upload it with"
Say "                   Realm settings -> Replace World (back the Realm up first)."
#@@RAB_HUD_PACK@@
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
#@@RAB_HUD_PACK_END@@
