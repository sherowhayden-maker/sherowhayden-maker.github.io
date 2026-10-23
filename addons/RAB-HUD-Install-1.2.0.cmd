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
  [switch]$Force
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
    if (-not $usesScoreboard) { $skipped++; continue }

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
    foreach ($e in $entries) {
      if ($hudUuids -contains $e.pack_id) {
        $found = $true
        if (($e.version -join ".") -ne $versionText) { $e.version = $version; $changed = $true }
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
      Say ("        applied to world '" + $name + "'")
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
if ($skipped -gt 0) { Say ("    left alone     : " + $skipped + " world(s) with no RAB scoreboard") }
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
