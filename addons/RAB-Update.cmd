@echo off
setlocal
title RAB Addon Updater
echo ================================================================
echo   RAB Addon Updater
echo   This file carries RAB Scoreboard v2 build 2.8.0 inside
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
UEsDBBQAAAAIAFpUVV1G4lgxXzUAAHq+AAAPAAAAc2NyaXB0c1xtYWluLmpzzX3bctxGkui7vqLUETPTbTUhirYlDWnKh6IomyORVJC0tRsahQINVLOx7Ab6AGhSHFsb+7J/sA/7BUcP8wHnYd70KfMlJ291A9BNivLMWUdYRKOyClVZWVlZeav799X2F/x35/59pY53nqqTpCj1qIjLVP39P/5LjRbZNFUb0eNonUF0PJ2pKkv1KC5VP4/r7EKrylYaqHvUzEGcx2caIKo6Ho9VXRTTQQQtUCPPdJWd5Soval1t0hu1pk6kzSKfXkXqdKJLrbIKgFSc1FmRY9k8ricqzq/UDL63iQ1MsvwMwLgRpdIyvsxVcQFfridaTYoaqg1VVdDPKim1zhV06apSyVTHuerT0Khr1IunOi2L5FzF00sEmpdZXlcqVmVx+YeKx6mynFors7NJvTaJ81QlxXQxyyPTi9NJXMs7tX9CwPliNoJOpVk1n8ZX1CNqVOXxTKskLstMVzR200gG353GIz1V+AVs4yKeLrQ6KwBQusD9WaPnZJrpvIaOA2otPtynKzUuSrWoqDWHOKURVzRMDV+5zBLdwsUkrtTR4Z6d9TnUuCxKoIs+zA78WsMxwctqWtTVwKDb9IGJKSMsEvWkcTXhl2ZkRX6/ACqpLrM6mSAoNb92CR+0vQGKkKaK0b/phOgOIIHugERraCLR1LNKVxWQy1CNdBIvKg0fMT3R77OqxnG7Fs61nleE6wLGI9PDk4Kdw5cwS5XtxSsorrMZfbou4+QcsIZfFQz00yuomyWA0QJe1zjT8QXAIJrt1H4LnUyKPK0G9JFqUiDR8pQKtnJ1OSmmWs2yfAGrJMDCTNYWojRXOpkU0ATWwm6nquetv96QvpDVAWkBds+ZHrjbgO8MFhZ+vlfGo4jWbE/V8Rl994v4yp1sNi/KWn2lgIoOdtW4LGaq979gXDop43F9v9Il4Ka3dQcwUtXqF557wNtVVevZUO3Dvyc1YFp9UNvQwtYdgfx57/hk/+gQXvZoEdsmTk53nj9/d7rzAxa58Zji06Ojl+/2n2Gh7cUmYvEdYTGEO9w52EPITx8ffvo49TFrwF6dvnt1fPRKvrU5FwLxenO8t/MigKlqWAjnFuLp3knYxkhXtS09en24d/zuxf7LlycBENCMLt+dZ9NpZWGxt7tH+4chJJJFUmS5g4MevTx41+g5Lc53rf4f7r0msBOA++WOUhMdp0CxdbXJ1ezv3hBKUw0sunpHK08A/FcMA6swhuVqyuUnlY2mwHGqdzgxqZT7rwgmA4qA9nDeLFDwjqDGWTXBjwKTFhjvDUGcAV6qd5dFLuX2N5XWRR1P3xHe3um4dP1pFxA8zcS70dW7Sx3PbZuNtwD5wRLw0dM/CU4JimvIjDpcymv+Qe/p0/Ka55Uwh4xD3lYj+RCs3jX4T7gKfHacnS3KGPdT2ZrXdJrV8WiqDaey3H1AVbGJozKFl7O4rpFX0CaxiTwFeSBybyouxvTjGLilmul8wZzncgIbLu7WUMiM+GDnX94dH70+UTG81Dl+mhhUqhNg98CKJhnsAch0VbUoL4BJkzTg7RpUlhQz2mHGWVnVQ/p0Crx8DQYFzJxApnFVR4bij16/e7H3r0jEbwBZPaBFZI49YItAV/g007RN4qMgVfVkLlTPwz4gOD/Hd7l+X+PfuphbOHi2lWkVUQ1viaieLH54omWOjdsFAO+axN5rULbqBWSseh7Vqt6lfHtaVLAPcgOd9PrWLO+XO0/3XhrUGCxtIWZPs3qKoglsoSUOADZUJACaSHXy49FPp/uHP+C2FXvyn49valooHPENxPmK9hvoIeMd3hyZCRD8w6sDMxMere8KVs1KeSEYt2vkmZshn0P96KHe4zvP5FH1Z4MuvvOUfiqZhhbHwT0JSHApt3kOv5SdIp/P/IDPyvCYSx7cax4bTxr8fimz182DCBXK4zxIkPD+GP6o30EtJEyDImhCCaEaOoWi02KuDM0akpXXjqEwocLrE0OxSLCIHPijLBkjmcvMkmDUB6QNmP0AEYkMibKzSI8o7VTqwbe0RrdQmmdZdA6rFWmL2ApUms+1pSbLM7ahIrW7IyyNKoColYsME0+namND1n9RwBxOs3OQ5dQlliCPAmT4Emqqx/EC5MdKW36GIv14MbXyKu20eApZQBtX0BIeCYDu+Thh+vhs7/nOTy9PTT+/lMsEPMOwnGtYjV3Upz/uHeyZDfsMhNhNelIkISIVwiv6jIJhJXBs2EQJR8urGhf+ppF5/v7f/6mgDJ6kGA42Ba5TbtEu7U8fx/66/vQxDhb1p48b8NtQGjTtLeZPH0f+Uv70MZFPeUT46WPqKJD6aijv08c/wg9ZBFwiK+DTx0e2IY/6pbaje+oNwX3AP/RPrnG9Blg71LJsA6ylLaylFmuj3xpr+suw9nAp1tIbYC1tYk23sEaSQYC0/US3cTZq4WxkcTb+fJyNGjj7Y4CzcYCzr2+As0c+zsZLcTa6Ac5GTZyNWzgDCaaJtOfwqo21pIW1xGLt4T92fSYh1r7pwppeSmnax1pyA6wl16/PWZEXDawdwKs21h61sPb4S2ht3MDaoxW09ijE2uMurI19rD3ysTb2sTa+AdbGTaw9amDtQ7A/GKHviJQh0bm+qvq8cQxoi32pz+LkSs1LjXsj4hha5SNExftuVcO3SXl1BSjScgRAlQvK+zBE1CnFpIzqxYu66BlFXLIoS1RWmc2X5kbF8/k0Q12HdHL/9CVtYm9Io0FnVtzs8Mfh3unro+MX5ufuy5+emudXP7/q2Y3QbMrUFh50T17u7cFR1tQ3cLvPfwjOwsn4DMruTGHg8Ahv88V0Ci/Gi5yUkabnu4SO/oDIhpsi0QN2XkC2Ih1Ln9+fI3qMgD0gsDfnbwFyHE8r3QXsSxR+hbpcEHyp60WZC8ViMc82KQ2Rkj/w7ywhydMsg4km+jpzIsDFptrgp3FJK4l6xG9SmMPgBczl3mxeX8mcbZM8x8dAFJNA0ENxt6zjM6t2tQpAOFpWRR5P1ejKtGUoAIW3YoEkheriSXyBIiHIrvXVXFsZMfIXcjC1tm+vSr2G5MoyG3QATpYscZ5MUdU3u5rHGSnb6OCoqnl8mVNlqoHSrgcnCCoL4hykiaFXMLcfPGJIfCrIxjCJ47OBmR543rLEMcLT1HaTerC8hjX0i3AiIqP4EgDpIB6d6foZ6xVfiVqxbwiW6vJHEVVANVRxe5sOmoCznvr97/HdwHI2bp8P+9vqTydHh9E8LivdR6gtAcIGGQSqS8tSBdtmBWrPNerViGgFNKrxy2V1Vy0Ub2iuJVoI2NioKFCPD60hal1ZCLtlv/Sho7+8YFo9lte36bMPpdoj4JbtGLyJapTLqDz4JsSW96UPS0YZfBu5QfBZ+Qa/94Bcy/Al7aELCxktxBbC+r3eVvBt3lDecE3iPWZQ9MN+kX65qh5qR4jaNz1iTXRIAo7UexviuDnKN6NO8qDXFqKLKICDkC4ZFi+akiqPfxkOxZqmpCjZ9PXpb+rTX6H1HLhHpHhFV357l2VW1zqHTX4sarCarA6khYcJIN3Vlfq3BYx1niXnajEXew7ap2jY0fLpvFB3cZxs4+mpX3+1779TG4JpasPfaJa0JRy9kySpLIK3s/4gxD0zXeC5a7qMrXxQ1TBY2PxBOgDMpMy0t2BgBdDSSKP2zskEYWs4eLOHCO8GlIBMU8OROPJgmT5qR0NeH6NqCmeR/vpQbXwz2GqQyl0WLaIsT6aLVFf9emCIUja1ehnHCBDGm0w3wqisE2H0IanaAez1fH1wo27g9tS1pPm9B9T6wgP3BW4f//0Ac4ZmuD4s7V/U/a8Az2W5mNcyt0hGwBZHaJGBDVq2skp9dZ9qs7iE3/dEFNoD/R0T+xTITrT9yXZXLd/uhrxf8Tiz8VXfbL2DwVa749lZjkuOeuZ/ncg1+DyqO40I44gPRJYsBTk1Qzte
XtR23aNAFXMz1oIY2U3ezK3pG0/vlkVOx+4PBZYkLLSPpBB9xC2PxtJ5QbKwWvtV5rbIErgkQpGP2kGVPojrfEiik8+CrbrMk3lEjvMlqAST9adIwsjyUXG5lhQpquiQAehyDY3Z3FRFFna092EbSC5ELMjT6QNyekgLwiniEBgddybyJqm43MUzWR8OJr58jevdjt+jsTqS8cCA64iPc2+gLmGATkdm7DtkLgWmZFSSyKMKlhNVmo3Hmg4nqCn0bLtWnEXNnEZTuqaTDbkCOD2hJwBvWnXmJf6dxefaR6uRho2JFhsDWMIHMMYZ0FlCCkfCIkmrpGAFaRgPWyS5oicAm0dosY/i9AxKspp6hudFXKIgAvdJdgW52xDfUCRtGHooYw+8KaABvURRIzjhJB5tO9E2500mER4KSE+EpBH/7gTnswVmUd9z3Xt0Rlaf/q/Ckyv8lOJNKjaT94NZnEk8z+p4mlVszSJXEZhD2FhYn3ypaXClnuLhFNer8C+cFGypQgePUNxXs0VljrUz4iWIe7Ht9yofNPKZ2Uwfwv/9GI7ywZIUNh239ggpGDULWHkR1cXL4lKXu8BFAfMIMwrfheyAO3gMyOrz46rZwu1DRgQdMXNE+5YMg0sjxPrQAAwGjUnDSeUDUbvRrDpB4jKdsVV7ZJn3KaB3sHfwlNoIzlPTOJsd4Wf72InrRmO6aBq1co5UIUFqW50QlqlF6n1vsGzHJRmBqnW0afk0AbT5tJt8Oqb746J1T2a1cD3hJuUxNVlB94L15y8bw+FZsPuedVp/U7RmsC1YSQpf/bWnNulN2A3grKfAGpqMNQHaL2b+vmVOGcBEt1pEbcAblC2vvzcPm84UKA3xOt7H8wIyPvZxImZLaiNoPUVGRfxpE+eC5GOR1fBHViJmYIQKdyBidbDYYTYuNEvOsgvFU+CTQ1XAu/Iyq7iQtzjZ89CDhpROqbec8SQDEu04ex/qdehAbnFjjkhEK3S+NiTt0zeeqZ2YCfMEstn31JRoBGGuqDJOmbdBWc+wjJ3CqOuEKeb2y1zB2OlsyEZ0szuJZxj7q7F/WEM3kzsvMHTTEmc18Qbz6Yb4Q3NDxqnbDqjKW3y4DyNxQ1EbET0k0GCj93AXzMM9aeketWQQZTzUpOcOD9Bb8rjCxsXZzjuzlYupJhTjBkFjx8YmIA2QJxgPPyI3vj/g5i1bMK22KTRgkc4LlQ9/noREOznyjHPN6sC+caN8FG0MInUEz9walSLZl3pWoHYFtxOcJx/tOgd5Y+99XcZVvxDMA7WXICQfF5f9Ap0K9Py0mPcY8e2yp0UNa7G7eFwUNRwdO8vorM2bjRhiiV2H7kXGpOm5m7A8JAWTbA4iOc2GbBFEbZXWubiYoJqVgU903aFslYY8BZuFtsvOvsFxBI3pSwVPt9Ky+cO9taYtLsvVeradsoyvoqyiv30Ahx3TU4DkKHPjW//bTR2OHXEUp2k/l/Y7j3P+qUh1oM/fKtBFl90xOiQL3Cvs1BheOIsmQKaeCGG3f5oY6p5fGs7K0gOgPxOtQyAjED0L+zOzm69trK/jqfA6DHzwqDbOz6tNtt+otEROMS+Ls5IdSp03FArf4QFiBpJAeGLKmW3TkUL8CMidVYk/cnhyoC+jlgPPdujzIZ3A/VHH0HXGGDAj3PgQGpVx7ABVT6CDEzjaAVO3CnaqPgiZlXEbRecs66azc/jCeCv8ouJ6U4EUJOa0Y52Ui6wm+xawXrEosTGJYb91wM+RaZGzgwMeB8APPOgT4wbkgOMA+Jt1B/w6LgEoDaBHAfQfPeiX+gz4ZQCchv147EEf4KEnCaAfBtBff+tB789mBZw9pgF8QvDW4vR05/jd6/1npz8CVh8yS+xt93AfhwNj6h+jyeVInU2v5pPKOivDWY35fWX3MH+jGxd5vQVEBhsI7ISXhXfixjML+2nFuIdXxTRLkdq8nQR+9edJHQh903g2J0PAQVxPoln8HuVgfs7y/oN182s8LQqqjbKzWVncxhg+7Zooi0We9vum4fsK2hiorxxi/D0eJx5tsCj/bPeiUs91XPe5wYGcCE35mi13OF6TjzcORLhCdkAU4VWAo8UtJkvfQyfXramN3tEb+PMdr4VoqvOzegJv7t1jhssr8ck2l7/J3kYxYJDbyjxBZ4FcXmDS92+9gzHLR7YIxvKAlBK8zVmDzJxOKQT9Pf2BD8EAoWF82OSOMyxIO0VjyribBtybHZwy2+yNJrlPzd+nHuHMPSBOCj2Ah5bdEQYkBvRFyQ/4KbE8QjvmHbqudXTCjVMmCzkQVYF+d5jacGZfZrn251a2cpRB/Xl3KEC1PfA4JP8yogVA4jbK3hHiy4iW/MsoI/AI1ScuhiWIRnj5O3g56L01ux1AwwAG+IVovqgmfTmKiQYDi3VKjZ0bbzzz/n3tfZd+2v2QDC7tJpODnX8hMur5SwjgCEVIzbT7PKV4CKvut+/p4LkLu4kWO43Dqs6rRamPTFSEkbQ8IeQNawMkQOIt2WRomt4cPf1TRIMT+zt7Zr4dulJ2gZBi8dP0y8lhwVjyyaWNSq2Nx4kHVkBw/qYgT9h+94NOGhnI3/3vWCtDPEVmecUxIRXFOtGhqmIdEO6kUOCkqA7hER0BUdftneq3vGIbbbLd7jXImq7XiAMOnnIi5l1vKoFV3LWNwY/mbKIFCPsSjG8n/4JwFz4yucbo0HyfTzvJJM7PtIg8HH0jASaJNVThCMzXB+3R82HHIcCCbt1oli2+hjxsUyugfuMkYQsC8sd6ppRND+gsDseeiI5A/S5rAqoXszyrM1Q6wqq+goUlQvQNJG2ficHsU5hd32iWs9SzgngkVFxLO5khGsMNgL8WUeMDcNT+Xq2bLaS9IKQul4Z2mnZPh7xOvrjDSCNwmi2i1je4/ZtI7rafQB/tfsYzEEXq36Sjdwv/FBOcAovIfJyPZKZPvYFXZPslfeJWmM+3EdBfMoO4b3kN3PRcY2LSRK0joWkYb0hHGufTdJUfLmZ9Y/Cyap4m7i4AdwzUdWY2WpymvvCC0WMs1d/Di9sR5LNWN5eQpPSx4zTp1bkhIg/1pWrE9iECcYfU+QRDCVJFoSde1NSzfz20kVO4WYY+3WFY1G8YBYLgzTiQ5VEgAWphlP987PpssbMD//OoELcB6OoJTnigGPEkJqQSFJMCSjBNE08RNUhH77Gu5zUQzIxhEggzVOu+pqdt5OZ4m3Y/O1sM6JMb7oZrkO5KUEfVq8BCgl8J2lwJq2DDRbIK0o+iWgUnC2sViF1zq4C6liNVaOxqJn6pQ/2GC+DsmnnEHePB8l74E37R/jjJ6rs4y7YKzbn1mWCdRVIsQAQcacUaOQVrgNfXkN2AUCEhew/Q/RzQk42m2j85k7192WgCars5VZpmAQEdIxOytLVnGmMbb4ZeS9OIXe/czG2gxuNmC6ID4xx3doDLwKHcSTHX9SxYRmw0WbCge6Nl19EhinTb5cV2mx6Fq/UGXWou744+YXTdLi3q2/TI5wk36E/IQjp6QxF9r4v8s1aoYzfXrFCfL3V8/HWWY7CghQdAvwOwC5Kcm6OtjVgX2h2FQW1d30/afFf1j7f6dr9Okb3RWX6PmFtT/r0Rkjp4pJOAP5O1NvsIG/Usrl9TUDYZNTk+ez/1u8bvKomjU36+gFFx2cNQSPgzbJYlJSBYAHbNcwsKeCX6liHQqTy2YKpLVHyjwpweWuXxe42lO+91u0yfnWHZHvxplc0LOqFg2CY/iabNyjwy8jcGK6SvND+2kPU/N25ddUGGsP1nyNwX+XleXOaIanv8MBkF+LQhwhG8O+EcGGKiO4jneOrGpkUuylK19kTMIZIvQ2rjWf00S84PmpVbtWcVimAIjw5mSDfki5qcS0uSLAQEpLIO2+poiWLZ2Vm3QI7pjUWXx3p8bW+oH4Qg9UryhaDAyJ4L4+mimgwIbZxkx+ItE43NZc7MCsMUspr1VORJfFYWl+TyhB2UlB7YDjVs
M4CwbxOH1KN0iGNmTQ8UWktRLKldTAKTiBSIZKaCCas6rLNUZsJ/PRutq4MKKqxljbW2qMsmK67DK8yyQfqKtl3WNOAL+ujfxK+fbONB2ojW/sC8rZxhrWapq9s30PmwkPScXPfKBeB2jPHzca4Wc46rqVA7TBlRyJsASb2ymkmXjkGI6A6bMarFLDBjCBUioVuMMXlV6HqM4Pe2LTUdjftzUR93j3wxczbZ5fbYYAqGrrHr3HC7cNnYO44DeoKV70jqLvwiH3f48x3No1PKBMaWJk0Gcho22cRATl4lnztsUv5/huPxtIhT2ytfXjD+c8ITfRt6lgYWdKSACzP/3e4My8+VS5eMdWXw1gu+e4I4viDLyuW1Z3nls3XEnhsCb8DK49zN8mewICJgjf3BwHj3HNOg2a7O2ZBkG0AuO71yHN16M7E1XZgkWuHJQI5uOPp9nNTiR1WRupukCMpglZbZuMbsFpdai18PWVaplcp3iMWdozF/6BguLh9ds+vZ4UqNiPQwcOZjgDR80JSrkNbhyoSuXqo1amfAZlXnrQiw/npg6liObOrLPfzCV66dFZMX0Ga726SYTGvfKpXWbYf/Tsp3JCxtdqw6u958S/Q1Pfo81ZPPHb3OLZtRGeRndKeBDRY7Gl8z2x/LIr5o0mhyy7JDLAwn3e+ab+gVGnLLDEhJqgst2XW3kySYI0hT/OXErLpNtTFRX38zUw828IzrnuBfb4mki9LxbHEQJBGuw8PAsmPxKXC0PwlJn1uAjz4UWnUOSP7gGOx3DAbgD31g5PIG4OG6QeGEWZxgbYKm2gmZaGf4OKPHCh8r6+c8C6p0w0mhfSOI5aSCmIkEvXY0iMuZ2B6d7xBHPK0DrgnBQ3HOpPiw3tcz3/E8weP7F2G7TcgBqi06aIFeg2qLCALuO1wPPCx4MbOzGWxywXGVmXwwp/QYjwCwRSOV8+mmigOzPbK5n/1wuxw9qtDJw2lkM5xZ3Pr6BgQWSTbAYdLuuE6GfpSmekOJc5Tf1ZvsLauJnetvDp9ax4P3Gp266exqjPXmbDSl7JmUsopORyx4kJy4dwFHwipiFfezTEfVYlQlZTbSffSmxEP09hMPeSm6FW0rKkKTe7pHNb39JJ6R/5eFod8nxaJMNA66/VZ+lJbf0DdgHvBvhKLDfsrxh97Rkl27nMgCda0VDOsNle8TYFVlcopnCC9nnlGjhupIBjMj+t48mT4BuuUkigpDs0cKNAy1Ab69ZAhMGa73XIsHIC4PD0SW6gYSzwYbZmc4PGZ/wEAwGbOp4g3bql0C5HQADqU5T6aT9p+02reJBvFY0G7VFjfaxOA4THWJjWfo9oD+ZUZ1bPAKIhgRErAkDshJJjo5H9hOedhvkmjTYZbx/6qoKFYupgPNS2m2b89kAVELsExrJzyM4iSbzafadT3VtU44ms90D3NG4VE6rp3PJcKHH31vpWz4cPQeuITrR/S+0UNUwfUd9BVppMMqV6RvwO/gYf/fH4hvYDwqLnTY2F+CL/8lbOYvjS9nlRUhq/9d1n3o91eKHNCgHXj6S+CGbFltCjPynXoQfUtLBRv5Tn3rx7D6dgn5fFcc6Z0Pg8C+iGyuU+Rh36jttl+EXWge22fOsQyaS4MAhCxfCk2FHvB5yiSHH3hCzFvc/+7L20FUF8+z9zrtb6CrGhV6r7wtlbHFXIIeheMJH0C+wBDp0Eq/nPqlLYsyhEkak4b6Tp9pMCCnk2mAubXPQF6SvHS5+Ui6bhPneTtzs5ZnFbE+n+hZyF0K0us1q4ZmC/EdDFPuNas07AqSvsRPwtesEej9Gd5LzNeE9hT0DMup+ppgpFMXCJO+rwkj6naB6krp16zRpfh2vpBhTk9JnRw4p4tXOgaTsp/66Mo7RJv8uijcI8iypMs7QWpnhmJTH0ukFC/j5FaUtEhIxeBUo7ESn+ijneNn744OwyS3WOsdINjnEfTyKO83z4bOVLBUKRh8JLT9s9F/kad6jCQGyxq9w2D93r17sdL0b5zIWj4oT6Wfxtxyjdoo6Bumk7peTUbuUXngAime4YcUxNTpohY2oTy10QcnNk8L2hV2o2fs/ncCL/Ypz0vzXSQ52d15E177yig3QZ4uqeVWRS511rFqp/a+0XKZMpvM5zTSp27dUCfrLyA9LS7XOAE77RKhOxQWkAnrdvQY5mL+RxPkoelsSJJ3PFxe10Wmy+uVfBgxeeW+1zT+NUp9zcZnUN5TnJvDmHPC3ID27gaz5ejot6bL21OmS+HhOxJ+8Mjpep/EUGbpdk1stVB5LbR7N4Qptv7Bm9CHD58XM0UsCSVmswNheKq3A3F6fwyFWpTjONHLrnawaSLs9Q4URclJpY2jMlGQZGtAfxNdD/27DDpvfzC3TuyZeFCE/IXjRIccvPphk7W++CxdpljboRdRKu/JrY3DruCI0Ig/zXIy1LUvhuAbITKOJYVhYy84loVMe5SsQRxk8spsq8SY1kxEM94lYSxDmIywCu52WMyjxiaKebhvkLVBrIU+I7O2IwdlQ95NKhPRtBjh2saf0KOV0OHZypJSZPIuiwGDghM41zKVi0DHP1Bi4yeSxvjx0n6R5Sq/JZaVuNQestc5v6IPVxfzF2LIpIyJu/YHDe+FDEUMnW0zmyBtEGwG58Eho3l2cceRDjB/STNK7+FcbbkjBL443/LOEfii2Yx39vHke4Q0AmYo3G8Fwn0DzonzW54E3wAKBXcZgExhCNmQ17esvN6AC6T0LSelN8A88XzLiucNGJbNtzzZvAFgBHMGEeIJQbok8UCVo3xw/yjmqWPgKCn6FEeVld/KKGjFndRcGyNoA6l4YGh55Mo6EnhI7g6TuSOg6nNv66CF8OuvCpVF+ByJp68skF8k8NG0R6Vw6mVXEdfGLmV7KbiRXa+R3eWNAPgHI5j62Zf+wHn7xfrNxE9ODpz4ATlnTFrTy0k21eyOgQH0cAhCthjdaSDFH7t1QwgQIpiXY1Hzug3WHxrzan6+PMpMEn86DxBbEqfIlNgvWvYdjeH8VoNrUo5IvkJ99Tbc0+kKGrTJURNGFqGmNpcq+mnbYqW5TRdLGWSDPA73MFIH+oKKauXyiPA7UltLDlkWC6w2VVKuYDi3SXPusDqU8N97Ame06U/Ugw0MUKF3LgsZ6VKEWEXX23c504XbShsOwKVSt0HoUZX9RTsIkx/d8Vd6bVKouwmk1yb7uvL4KBX4XrL22avnPDp99Yhhq6wMceANn0v+6Yqb/o/y5ABCh0T85cp8b0F6dkXiuHwZYMK6KvODK+j0oeMHB2SvAPC0xTxEvtiCGJZrknLU+yhqOmmQFYkqCEMQsYeujoITC2b3Qk2zJBLj5UgMIcdMg+eUjJis+gLBLaGTxpqBJb3HCERGKzphIJuXNoqzq3GKmcj0XfLv4x8MBB1yUmvK3QJvTNCotcvSWw4MpepyAYO8Rn8FszwsZNgA8V9ME2V5MtscZW7sJQCu3DVJ75qt7Upru12tmWXiyoPWdk1rTrlJVzc0og181cQtD32eukEqF6VUtieYE3jF99FwC+2C6JmugFRSmM3g8EiJ4ZYcBZeekdi85R0EHVt2YZp85PQMXmSFtBKkUd/c7HwnkaCNE5g0blVD/qlPPsiTYnVFvBt5Z4HlTfI6oZt75BYOrR58u4b8F84as4wzM8mdHFvuLh2++Ce4uMdlQeRbzVz+FVMrGmfTWpf9/jltf7S1obvT+cBLxGUu/GB24Cfahe2+I9WuFwKO7Z3p2osAoiVJAhJ2iT8GhcYGJsluaGstI74fpOQp8uP0GrlxTPMB9qaaHImAkZDOtZgifihCtlJ9yfizmGrYHznrzpDya2OELKpVUczhxrCjyIwwY+wFgpn0EFbc4WBUNxV0j1zBRaSdpe5qypfqoe9sUuBxDhPqSsqgIEGQSwfUSrSLSDQxsohBaglw2EALv7aIaSmhbquWGBIvoPW9yWzhxnqK13RSJx010CHGGVfiZCEpeSUT
YjFDSq8xVxTHODeP1K9gMjJ92QdZCwjtcbdOsGPd+YdEfYWlN1gLnoSNlYz04yXOeNxnTQKmjJwComBrFqcEqoBI6ktKQtM2rovRIDLXRtp38SCgd/kGN2OWJIx6IGIkSJtz02enGOtag1b35bYOWmE2RR0me5QMCxVnqhNdmf0W+lr3e3+Wk95SzSghZM4zpBZ5fBFnU7xbjHHywXikPye/fzhilGdOe0I3B7FDSjNCAE8GgY9Kvmh4HYljitkRsPzJNnlUoVNV2EkqvW8LreXwAbnIHPTMgajRUKMV27MHLxBqYGpJsclzSCXtmAep5/xO8yWfgQLxDGv080VvyRetB5lg2crAGfn7pjgf1ItmnzAcqx+EXjSQbPLIeKIBntzU70xOEuuYRXy+7aEV0WGkQrs2+eSsO58cctKarXTvavl0zdibCccqSnW5lY7uwhAGghycsxuSRKj4/AsSlTJ2XeO3ChsF+esTMF63Clxo5CWFK9lFH3hSKel9mJGj8Ct7ROTFRgDfCQ+innsebOLCqulrnm+1/L7GulNI9oZXcVlnSTanHBituPcWTJ9b9/ZTL+5dlK3rn+ez2d69pR0vXLnleovbly8dkOM1FgPZ0F+U9wQTHq7I6ZbUh9KGPYy7cbUHZGKgw9ymLTHi83p6w371eoPAWiybHDrloHej5ALDe5kbZq9G8lbPvCkLQGy7QKan8VnfXra6RL6UNDTNAOrqFL6MN1Am50HG3Lt36R3Ha8CD76JlLm61ZbigoA+uEA1aZtRkh7CXT6MaYUG5LTWmAyXXV0mURbdgkokC7Q9ri3mEpu9pnOWcRNnBYyBOrks+X1JuLrR1EzWjDydsx3DkrgCxQ37GPGv+kMvsDJDuj9p48eLvZqZZ8kj08WRBGhfAtBDl+bJx999h9xsOmFmOblhFeXXUMdeeyAJwQUzBbjGbw7BhSXufsY31QhECK3+P/0bQWB0j9oDvWsPnyh09hAr6jrSHeGm7EqGVo2Nk9ryWtPHc5SKakCYpcBAlCEkaw+shq8kkAjjBKNl+1loBOOYsX+gtMfN5M5rV7en0dlTpXJAdAQTh1qBbk2Wi2OytyX1ZNc5VMavdwvGXjT+wCM8iRzl5XJpkOm3OzOebnVf7zuPg2llYPg+YW1kijhE9AR1ZFC0jFtvKB5MLCzniM51nbBAK727Krw6LOku60mXntHc6N3kr11Hwhdfod+oxyUxeaI7/RQnl6AhvyNMD5hKU2QuTXn36+OjT39hGSAw548QiWMQcDLlT1CEArzDMeldVEydiLh9XV3miXIL3uc4PoDAMegDkLbKw8wtcG/FljJf+0n3e/fYV3muLbJmM7mfw6sZDgv2lfnqy+6aEH0jralakmLk3zegGe4rOiAzDcR/duIEzTKClOMAboWB4hJu+d6pxkmbDd9E/0pVTMQlQWrqqw+ZHF+NYRZFfQve9GMTisl1k0Q5NDUrQQIRx356DKPsWomr66eNIqMbcRW6BRkV61bdHrp7c2wkbvmDdy233iM5eD11hkD8eYODIJb780tYjumGWDmvTN+tvu2Gk+IEUtwHY7CKnPkGXOQ7+iv3iDHEOwhg8XSsW9MX9Z15LaXeP+L5cGao71VVidg2+TVfbim63isjW1vVdvhHXAYpZr/PzRsFtOkoBMpFx8rSf70u8TwDWDBMyKTEHHXMTxgx7rTTU7IMlE/OYM7ldYLWf945P9o8Ol02hvVQZfsuHfLw6G0k3Ruzly83qdAyECZfyJdX9u5m7O+CbWJY0Etzg3NlIYIhZ0op3z3NrMNyKZ61Z0oa9Edo1UEXWkNNdBy+MhhMx3xPtVWMrOM3mffvS2L6Xrw0xfauuRdK2BA24uuM5i7ou8n7vqVxAT1a/nK8liI8Oe5zqPjl6/rw3aFU6tN53UjP0urtZI8AQD64UZTnqdRQ+fEk3thAH7gRI+RJyCcrvBNH3HqyvS3bKjuLkmO4CWtWLPwJ1w+EwVb9XL7JukFGopewCebwL06ldCe5fbfEK95UowTWEiXl//ZU2mojVhJnc/2bF68CQ4NUPwVE75Hu+3iUnVnMCkV2UjAwrm3kgzTgPwYbn3i3a3GgGkNTLduzuPbsO9mx1o+24uSG3Zr61GStrU2vsxU0O6+21irmKMcov2XaZfXu/Vm3B/ibsNU8JuO+p2u3HXdVka/arJVzNbNLd9XCfVuHntHyuY9P2WVNQp8Fda28H72pBdumOr7r9mrbekbfr17Lrd+2zjQ290THca+twY+/slezzXdXbG76t7NOV5QaPnsIJzye5NjtQHeuJBeaVa+rr5poSu0bbS5CNAXMSm/vOGhA6/czrMK5lMFTnm0vc5Ya2jaQNwjNuQD4M7Cg5zTEFW/X4OuzTYq7MXP0574UcYHR1mtF9VexaQ0aOQdNmMormmJk6hj+ebfLbIGrqLrdk7TPUh3vUicd5Qb+udO19X+CBjPfiZNLvY7JSPnMEdWkzzDhWjIjxUeRMJX6KakfXJOxhX4X0tshGZj5r2v5z7tBDbKADN8Y1ajVyzgk356tQQw19Dm64wm+LnJjfn98YLcR6OtCyK+6uq9GSEFqSVWihhj4HLVzht0VLg5uW0OUuDMnyx0NEQBalThcwPEwYM1Ql9YZSzSCmXV7KDgzzSQX3N2KPbh923xjYfc7ekdQBYza4nu3rLXbubuHQ7N74zz+Z837T5LxTDuPs9s+2RIVQlqIcG16JkQARLSGYMeARpXjkDdpo6Bz90vG7SAhRuYl3Nw3Bv4vN31qs8OR8m1wLc8nLQk7qtyCCZQcAQwa07aOuJjZXGOG1ink1h3mLem0CoRFdQxxm+vmbLWn9lVGTrZTZO3ArIjAauGtB6puuBt8G5MPw1ze74YnWUqcpWm8EsvVGQ7g20gQlejC2JvN1Pu6x0lOOfI8F470vkM5TEuzoG0w9K2V0T/QOZO+NGwnfFvhW4vfGLeXvjdsK4BtfJoFv3FYE31gpg298mRC+8VtJ4UKXS1tBlamPVpr7Yqot2D9578Ao/XYu/CATxfptTtgPg1zUS2L0/U2/E8rk/LgGTLoaQD1bGvO+GtBLabH+Zah95FBwCw60TPmzREvwp0Lu7JJqmygIjb5+vvfzwXz3p43jTq4yxpYJcuP+OXRwfjFHXTVaptFSQh7SNSa2oJuDO5t4fFJTdALfR4Y+haO4xks/5nGFcRnwAoP3ot7/LwJ/7GdutPVJJ2W0Zq4hE65grDBH4zGGYVzwUfWiW7noPIySq4Q2qT5uodarBKrSlkpvoww25PfAKKSQJO/fKU8We+v1gC6MPeUEhX3xs0avOmiTeixuVOyhLTfUlhrQBgLR/Td/LmHK6rf37p8N8fKi9uW12NSWeKPuwgeRN5nwPpQFbOq7c33FIfvkTYpupWhtTCaxd4e5TrNauip2MeT6dIfKUE2yvLYJtu0Y2r5CsDwOijSemtXRcqY2c8lm5yWWwVPMUoAKcfakNfGfaLvkkE3sWYWGwOsD4i3ZGM9sI4v6FkrGALYqxvTmOKzkbHEyIK/G55mepn3GTu8Ub9XG1eJykQeyn+AIm8DUTrOsfkoLqOVN1YJArMQn8YWNzXOHtMrKv1xridwJgIHAeRdfYI2f6QqkQRtLNuSdiBMTbPoVQDJqLGtz3QKD+5dkfu/WQbAINv056bizaTWNGDpQ4zib8j2qlN2CSKZBG8sMxEuIw2ciiFC6kLlaYTAOKedm9tziUnG7K2y55ghCYSw1JSNGGrOxwlfFgi42itq2vZeUYjjDYFsUbjFns+bc/BRezXfCd9Q7zeZ4czo7JuKtluYaZpOQ2FzCPFQ6OkNtA5zwH/5w9PIZVLbbhAn39Nz40QedLoUO3PgVk63bSUgm8y6QfhtoMNjYbO4dHgz8Bd1oSLakpcb3Jcvl1saU5ftSx872ZNvDRdPTu7Mhbxic493VfxM2/tYfslm9PGbD4w0RNnCtr94CG8OLb8xt1BjD5N3yDOLkQ29Q
3LjL9Ryy02b4ual11253jleEnRgAfU51rVXSvJAc/+PYDL8EPkRNWamwcT27CvxBvCXd90Ic3XI/ZsX3ssXeHtetmcBOim7O7DpLOrZVvOA0njMr4MVMdZCOTTJpDrJoW3yxHoqBZ+j0AlXnC/IaQ9fHjvVvEhxwvAQSiInMoYVIIUcSK8qRCHV8hYmBUp13tHYs/swEmmZVPJ9rTP0g8Xycnog0fOJXy3djn+t5fR0vaQYEhQygbyJr34rQh51noW9NkRO44yIehyF9arPqyY9Hr63IeLx3cPTz3rPeSt4Tn+AtwPY+8p4bwv88DrVK+LZRK0014/LJcMgLb+Rrr8lgPfqBMx+WdelJu0OfxTJN7SUM08ViA6wfms3l7RF09r/JTYJu3YKtkC/ZkvAhi+yBSXC6jJY+hyst9UlosaQfSZNuNCkUz02Mtb/E8+WIYvRNoLjkFqGDD+mc8XYGvqLFOV6d4kWUpgrdSgmHr4FnSm+5RSGrMT0ib5r7LS5mGt9PnPsVdCfDn7Y3OV3349p2LmNwHIFu8wfgiAk1KdJvqZ8VoPXl/s976tXx3s/7e6/ZCBIEmC2tSkw/v+JIZWDechcnzCie8vlXRaRJF02DLIh+o4Zz2plzXi08Zex6409YC5YQz3Ah2luQKMpOm6KsK6tU383FoA2Ck7CpmlPA+G+7HBHuNzuQ3wIlYrMNO1Jb0jJq9jbdBjDVq4Ct/w/NYpfbTqgRabDx34CPGw3KKva93hTJVkuDvO4nRCAYDiqrm07cfT5GbEtiIKIDPOYy5xiqjW8CGa8lGRpIK6qF7LR5Hlup41ntagQfIpaxzeqc/umPewd7xDyHpmzQ/PqKr67+4sZgmVC5ys9iyb53U/Pg6lnE1YirCGeQ+JvEvOoYjsIoPdqpRNrmSUT4IfTsuimk1fmPnMFv+TscOE2bMD3+ZvP18PNwyfsVaqLKOj5DjP4gzxLsLkpbu2aEz5At8zpkmhRb/zhsPvpcyoH1OYrTM7qRlNLiDNXOs4P9w6E6OHo2VD/vv/r7f/yfLgJCfullvV4+aDED/uPG/JgD0SoMW7o5uXSqplmSc3pCxloD5osiH3RZFrJFiSqY87JHElUGBxD3vKm0p/s1iVOuj4MIA6mK/KdKm3TyvzhJtUT5k/N0c15vbJyD1Uq+gadMbpoAXiq6+DduNzMRSoMOUDYLw0dsKkcvdqpdv7qq4FdULuCoR6KwF+JDjfgSOkeAqHalX1w8DFZiLxjAVjspP34bEOel5CdEAjhmGS+MqrrizIfjDPMHcpWjnG/piiXFN6YVJCMjpmpY+qGjvONTXiJgkJUpvAed4FD9fNLIvYHQ7cZ5pk7QGnTd5QJz41zBuOefiEh7v5XziyDzkkqmcTarPH646eUKJuUlRoRX3ASctf/+3/+pvjO89Yn69FeSYDEjOhwoY3WmgT1ilDU5D6HAYTJ9CTXwxew0mAF/nNi1uTXFOo3ovFqU7u55YSPLLnqBU4g+oOxS/luJl9Hj9sU6jXDD4BKX5qVOQeGq65Bumf+XK7XStV57Z1k3VpEV3bXE5Q+GcGvWqYPA9EJN7IcMkdd0EG7s+y518EtbpoyXp0RCNcNWvFAdEwK8idppPywOSvs6mRSUJTsdRArWleIUIGxcAnqlIF7P3Gk9mFjx+Ft3VvKmFjmq0vVPnPEliOWjAEEAvVEnGzvCsg1hFXsgy8F17CFLG6xhPzXMAW81lIyqqBUFhmQu8erj22/5uFpKCpwCo5Uvs4qzDdFRc+CMkqUe21BkWn0YH+/dhwTlYUIgukIruLQLQFqLy16h9cQ/IwU3VmHL1gGpeUVdWgeiCN1cxinpOLmDpDVkzx7J+PDTyd4xyd8YaFtJyjHJAUuZDU1TXQkO26vIqIqidjJI6Lo4YYdAwVJznhNL0iAOnSc2odC5a38utamQ77Fu38wi5QCSa7TCEu8ys3YVIQe/4IPskJz299tq01wXZ/3Qh6IoqfmGTMrXKwkDaDY4FHesZhl0Nz+L7jiBYR9vhgOptd9vLISu6GHclIFmTBxymE6Wd80lVze2RUhu59728pvotrrIt8ME3EzzQNw9DKsftGLOO6yz3VPcWiPUcZwW8UG6sxqb3bv0zVIW08bbSBopCAR6eCG5REUSIVPEHE8IeBkgkkAr3/QIqCYdEHsj2c1bmSKOgBCnZ/P6yuZzGfsiUYapSjSmmhjDwUcMM25mvzSrv7n0gW96kMzbm+IrkaHGONF0iyiSDKXLdq/MNQ236soHOeL9P1BLAwQUAAAACAAVVFVdl2PLufgBAAAmCQAADQAAAG1hbmlmZXN0Lmpzb27lVj1v2zAQ3Qv0PxBaGyoSRUd2ptZbhy5ptyIwjtTRZiJRBkW5CAL/9yqSI6jWh+WiW99I3nu8j4eTXj9+IBU8ldsM3OaAttC58e4JYTenqx1Cgvbt6LU5OYOXYCGt3rsT0Xv4siYPCGlGRA42IZ9I4UApkoGBLVryS7vd6apA57TZFj5ZlzpNCPOXfuB7N8MPGciwfeG7zC02Kgc2xihLndQMxVYRRCqid7FaUs4FUJBMUQUQs3gRMRbFYyKdpvwcjDgHGxY6x3JeWHAx6nEk8UybDZqtNri5uoYOwnl5dsCCqymXq+zgsRd8fHdrlidlisVEocMurtGz8hp3cNC5JXuQzyQBB6R5YMQrjYp72Tc+fSNMRrb+lEIyBM6pQMUpF+qOingpKAsTgRioUKzUpNLfDXimU2vMtGuNmdPsz7HGceSlaybXWQ/NxVWDayiTsSmYbVntszr+CQ4wg9OOG1nMhFpwKnm1hDgPJRVcBVRIyRbIGLIgmlRC4+xLJ9XiNgNt/Kfi/zFJ//h9D1Zm2KNJ0Eg9uQlqTJiqxmmjbNqPz+dqraK0oNxtgbZq6VTLG4lO373QX/mBN8EYc/8/ypaW+tqE2YWER+7acWTooF6Fo/8QVRCUbpfbi+P6g1P9B0wldp5IXyDVEk3RdOrb1x9DYlV1x99QSwMEFAAAAAgAiwlVXbUiUvQXDQAAHQ8AAA0AAABwYWNrX2ljb24ucG5nxVdnWFPZ1t4JERCEBAsg3T6OQxsJioCEoohIGVCCNFFgaEY6EaLUEXTog4jSBBFpJgEvHQMoDjF0EAgl9JLQgiKhSMk9Ge883/c83/Pdn/f+2M85a6+13r3Pu961zzmPzE0NRYSkhAAAIkaXDCwAgAHeEOSHLna+Bb/yLD8LQz1AapeZhQyEq66JLgClCcJbN3dB9m7vS9f9ABBt5A0Y1avAGbp5Y2Sge/Wuw+JwR8tRQ1mqDxfx5YWBy4M/C1B8p6I42P4D738v0fUXU9PtUohyM4jYbWCmi5w5/OJhtPZDoQkjg57krNiCMV3U20tKMzNtuZVJHXyU9tObz+aK5op2OPflHVKHC+ey8vPPW9bXMAPIoY18AkDVHtGwKI1FKuts3gG6BW2jwmC7cdzsDAyRo24GgK4YwDgiAEoSBhAXAQj/X6bVAUBmUEK+2ID5l+pzg+yTlIqzIEoP9BWWKe4DDfGo/zfzP2SGHfa698l2sd4pXRDs3xhAnnfnyg4ZAIWhSK/64LNvVyfGS6WRQ1zqKgp8XOWQtQLFgM7WKnWB60QQBM6b81713mKAuzOEXfw+E7SeI6AsxR1bJXquBvSLw8F1h+Cdvjzg+LO3POTeYMpnVe8H3A0q3XovAwYHuXJBHbVK6J13yfgR1xsJiwpAZW7a614Pf4MyO6S5Tm5IFzj21O8svxYJ49Z9gzeGxR0BiS9NdEhfkFnBE3wVMhXhANONv1GDk94ZW9PhxipG4xS+R4wj1fZU+U7jKn7qSwAN1wcXJqW2C5lZde4tTtuCIIOTu3Tvvfq6JXlr+WuFFhQSljewXcrmqg6fZM29qxEDJWytnYc4FtOtuKRYYP4iaOh2CKV3dnRlRpDkXkvDwjYLNsmUHVJOvltLSTFy/gIYOz/ImJRal8QdDOTcpAgChiFhy55PPleT3/6+
tTIcpEIJbdqkcObdlW3kQHCpKQIobXQz5cpFNFMrRGu/T3SNhNBL/GbbdbHKfY9Ag/bgJ528TZ2xoHCIiTG5xVm8SM3jClTtt9LzCAxqsKjYa+bxeOmopbtwaTFXksDfFw6sT6L7R7emaDHSuHb3LvtRobUdgbRKR06OKKzkllC41WgzIc/IUCpUG+7I15TVvC8l+JJWrLMU3PHIiiA7bXuD8DInISS/czvTPAr0o7a1sCuHwo9LbgRMBAqGxXVZ2W+fI3vKEPJp52u2cGJAOk9z9bDI7rtjl+QRDVHuittL9YRB9acUydX9VWsJs1DKp8TslVlt2xx0SBa6XwJWsq8mxstMOvJu1UctwTDZrsSxFde3lRe/SgUrFBJC3RJA/8G2P+jnu1zdbSZetugowx3z/V1Hn0QhbAb9l/juiwHNV9rLzJBBgmLPNF3JEL/DglI0RHaXuY6g6/IKW8jDcey3qki4guBi5o1PiRikSNfeV5rY1mggaEBgGYcskQUCNspjujLlZwwBIvfQOwvjB0LyWYgyJQQGY2y6501rJXSnYnPQW8RPabCU1S7cogAiusRt6SrMFwd24x2s+WGo1m480uNYxACXowDgXWm1no/9nMjcYBQIL/s2nlC4Pp7Iczz7VhtKdNPo/L6UKse13nbyXdY8BiBypO/Y6dsJIbesBeAKD8u11a8Ui7G1VJUhw8oMdac67qkmLBXKyc6fq+G31oP9vDDx6WeHmPTfy370CSY9lYChGnpGxf0T5jy+sFSJl2XojzbEAKwncKjcQ2U1UmbuQI+o8lWd+pV//AR3ZHrguSfVfL2Gry1hOj7jObHjA6DlMAg0NYP7iihf0I9K2/42p/iYje6c+61Y+KsCCCRNpV/fR7A8w3q8Y/csCkmSa40E/apxZPtcvxUThocWaUSf9uFI/XalDNyRqqbLlGKUZnWwLL0OM2f1hYSxcttQkdQrruS7VI0ksCzIt25LvDguY399xRAsPK4ZZz5hqv2ST9PFkiRwcpcVJZZLOl1QQDPgztpzdc5Pvf09Q2fxxsv9IXwrulB8iOdSWRLR5fWiOtK9/D1FnCeAAK2NV6qrg+x6rLIBJWkS5Ygd24KkdC5kBd8yTZGLP4P88vEzRIjmy2icm2WHlVxd4cij4JM25d7chBAo0ALcXpS4W+aRM4JpE3fuOQLCGgSBggocCMYCAP/vmXtFyZT+4eehnJ5xuk7IxPuvHffWP//ZEcLy/ho5v147y2BoPA/mJNyomLb1peJwVaI62yOZMZ4+m31oghJBDxytQtIy6rhEKnKJsmpKuEOZrWJntM/K2rCf+nUF3KVGYheDcLKwxLHze4w7BT63eVXf6ihN9ar7LEZQYrJk7LWJVU7tJhQ4/o7tRR7YO4se2ef/ODPWfvNKR6Iv1TaC1Mi4ydjHAwDG3daEeORovk7IsFxo7Iyy3X3FqklFF7NDGCgzpl7NxKLaD2eU7Mjudwo25a+ZVCxcS3SFGiui9rNntpcbvk7R7U2L7GksmYbBv84jupT/KgRXeGe/gmZtmBQ/UsK32lHqDg6XPlGnLrt68dJY8afS9UcrbDytcn04r1bmdrH0F+OxL6jr/dBHgAuVdY+DI9UXRlmTRvwqRoQVwF7GLrzdgEXaeMfw3SNS+bXBr8wlq51S5lQPsuInq97k+e+Q7hi25JHiiX/HSuVNemGp+9HaYvmG9L9QPadEH8w8fbz4CFzylmBAdsrtBvdqTZNhR3ysDbG2iS0Zf8o2d2ppvNlrF8SKUsVkc9+PAxFDb5KmAwl+fEUc52zNKGiuORPp7VIZwUMZ8nHJ96Z62/Bj2qeeO1gut/X7/tzZu1T1plwwjAtJwG7gJEM1wwqWODQvufqe2X6gLGOPP0eTdJuYARxFFcJBwWT8eJlQGINfu1VjiiT+P+5rB61gewXDfD162JKmMUYNDCWKVKNPNWMbTtRr7l2seoP2xTpX7LQCHs/e1BTitTf7mc2pzZQvTP/JLkZyOOkONJnkp2OQMN1eLQZ2s19AuHF/HAizkg73PSOfacpKWbjuBvE3F2A3sPccnYFiB5k12QmGIfBdstiKq0b0Gzb31n2lv1SX0EQSxCFAB2qKbO5Y72i9M7Kp7wSX/6/yQ3V8EZWPzCjwmVI6I2IToO2n85nZVF3dGC3OnJ+z/z2CPL2X+QcP9Qs9u/dDcjFE2TE8/JdXkIzOpZbkNylDMJvgJ2LvSxt25Vr/F19qi2XHUK/GGc7T1Z71BxDL8hHHMpX+NEna7JGPS7Df0KXJ/mYplVDsZeqxpfjEnh7FC/ktr+zbTCqDVs8oJbCzwk5C2607xjq3cFIQWnoN9jRdCjvfdry6smZGvZ9B+/DdX86YeXuUx996dUHtqGemxpq05lq6UqXhoXLIT8orX0hR5G1AgiKBvnw/uahrbeFWEaxm8vmP9sz24X3mQ2529p4lHNRfkltyj7+R1SXQJ7t51X3pCP6arsdxPnttHj1+GiPJSZtrGhXTmzAeEaWZn3wbo4t+TU5wGPUsNOLUOJ3LY5pb4NvWB3p5Wl5xuByZTUfPx/GWHvRxSUi5pyna9GTUo2C82imzaLFvRj0tjYbBJvD0GWQQTN5IG+Hh5shiV6/S4s5H9h1K1DR9rj/rnF3cCAn04+K7ckau6gnek7pRUwI8guHE4whPeEF+t0PUXxEs7cpSNZ7bmZqifQLfdi/b64m4/Os0GnHk8kjqKUjPliyZYZ+Mboc2KRQkpcOapAWNb5hpUiNyvxSJZHdMfkIj5Qp/zXL8Kc0UzXh9kKEA3qax1x/nvUrLocpchpgIoqZkNstSDwFTFGCmtKogPaLhecZJfs04NdLryWbT6fhJFDghGFbWnYNpW7ajqQ8fm6o7ge2DdmeeG0j1EQzbh8DY0KI9zb8dOpXpb6dn2tGU4gf11+XjZp4EN+PDUA0uBNoN2OWJlPnviytudKck5R1l+EJLa/C6Y1muX8ARBSY9rHb5Lh18On9TljlVR84w95uWwVZcnP3g3rY6g+YV8gEEshetH54holdttl34zPZjUi3HuilKnRQ72TzT2Rzbrsu0O+0++FW0PetfrFdcnTXHyFtgO7Kdl8n04dvHmCrieqRWmxWhTg0eXbegzitMy8EUjT+5t1mzTJxa1TuK3uNDvhFDDNkU/vuo+UFW6AeVdnQaQ+VZTYv3FZqWgYfMokM9P/GEGZN3gAuzoWPlcjScBEtFGM1risri7U6gD7Ic6stGxjUEeNXz5z3o6f1ncR+qPemF/HQLo4LM9D3+ZPtuOal63kbeQ3Xbn6cfPrlbd9dDQtxpeve1GBpmbfDYD2oEkzSlcF4nAahQRf4/qMReMO4jMzPe/hgk+Sid7k1OT5aqg59G/1J9gdewCmdJC1fR+rAUGs7NqeUhMQWRPP+sil7+qp6miqvqDvIKehK657/2H/R/zD40cKgmbE+Ugz4jXE/5sGUwzgeAfoF/+yovMYZ5bzb1xoQCVOTgFgUAVBdfNBe2eC321DrsdSX0SwuMLpgakPQcI/4JUEsDBBQAAAAIAHtUVV2IWkMvzwgAAKcRAAAJAAAAUkVBRE1FLm1kdVdLbhzJEd3XKQIQDJPtZokfUZYoGBhxyJEIiR+QGtPLzq7KrsphVWYjK4utBojBbOwDDGbhE9gLH8AL73QUncQvIrO6mxpJoJrs/MT3xYvIJ3T9+phuCuf11Clf0v0+ff7lN/JaNS3Nm74yNss+1DqtdKbUU+XHvNVRwHoX1Gy242yzFFHnyqpKe5orqxtamFBTFNzpEIytujzLnjyh21oFyFBL7Tts6SybTCbZ53/+nW7en55e3dDF6Yfby+t39Om/dHl7cXqdfe+M7egr//YOdl8c7GYf3JwKOfPpf9Q1Ws+7djlXxtLe/uEzHHhnmuarAiDi+e6z7Eqs4ds3m7fjgf0Xz0TDnQj5UkM6cKJVqL+l4uB59larsqtd+OqRl8+za2Xv6A8s/b2utC0fH/jzi+zSNsbq
rysg2s/OdTvlgH5rn10MptW01Rq7/eX+ruQg26HRiBOeUk0m5lky/PbHE9KNbrUN+WhEOOY1H7COVBGMs3xBwXLrQo1sYy8j0veIa+nVwpLjP1kcwsBnt/bzF/nudi5ar92CrGp1RwpiGzXViDXrfSVX7lXT68GcjiGLhDd9a9mUY116V9zR3BsbWClb4U1Vhx3VmMryLUAuXqCZ82LVkrxbjKmD+fwXWTHV6zky2ZHBf7ewEGZ7DqzIZOUJ0UEtYSpL1+wxtSoEnKohqHFwno+KFzCaPYR/yTXTBVwZjaamqnQXBvkz47swGo1pqgvVd/qRzYZ1wdIF1mDS4HDnPMycLnNkA4dxalEvN6xUzYLN9Iw9UvihotHKsvW4jXoJ2IE8N6Ou7mezhtO2qLWN8e6oqJWtNNvPqKhxWq9AMRohPtr/saMKefNBVZEYOJoNLFBlpUejIzkrzqWap+CgspszJFA/vL1wvilhmzItR16SsvYC+uZAtrOqIdcHtjZufszpGFiDtFo19wk6ujRBTWHA1tto7lO6ZDvx+5rtgspjEXuTSGl7vM5tb5pynfLGsNBkI3DfDyEbTIgByenNEACgoIjYrywwylgs1BwGIeuKa4RDOYm1PlkHMjKLxzLQvAVKlPXoBiDkFttiImMymSa1NfeughKW4l1f1REyLOYVTSLlBQdcfwyii7HZKrtMROZ1C/5ig/b3uQBi+NS9Mk1UjFCPRiuo1Xxi75ARmrIDuR6g4lKg2pSl5mrpbTANLV1PofeoeRz0UbqbzXKBUcyqm2sUpjSJvb3YGI4fNQsEgtuLkMB2lm02mM//+JVNe5TG0SinUy7rSD6dirmDDBvAXlz1YWhlR1n2QJdzTgg9xH5kApUONx6ws7OzQ+kT3xKMHigs53oj7RQQANqaNpzNv5AUw7oU/iRVsC0S4DR494HeuKYc04V2dkxnhR7TD8bj89yBP/gcc2BivqRNIXuRF8UBTl6C3pCzdI9vcIqeIhHIjCrqyG4SXyVIBlz0vYG4Vf1w+Pj+WSFxWPmHqvegdLgz1TOm2rW86C3bYh26Ed8+VtZKfCZoXnme06f/TAAl16eiStFy9ikQIDdiPW4oXEWNXVixQroYPWz05gUhF1KzkDoKR+goDgtjen1yfnaBsF6ejOmvZ1eff/lXlKGBrMFrSACoUR2lnqm+QWFt3XFTj+2O7ePUZR+WcwZTxKoocr4FDSFgHZt0p5ciUGrib2Ck1VxTgGaZxYGr4FyexRYwpJcrDcQwRyMA9vaer0PeSaXzbWOLpi/FX+PZJm4Grvf4VQqzbOm8yhH1fz9/c/n+ZLL9ihMtLYezzkwpJ8EjdzpaHwSIUQwX/nuNKlndirlFTMApgdPOfJPiIxFOfQAihDBNaHTqEMwmQp4xftOfNCYCiE5MwSCWamGXlWfjTduCqVXQ3OG5/Q6CcATlyoCNpMBk2WVpgit9BHLkPcOF9KiwxTBp8IzYmAspdqHcB4pSfl/j17rwPVL1QLvy/QceHgSjh3HhJrauBzBgXLhVvnGCpGe7cSXNbQ/0Mi2cMxUVfGf8Ii2dtS1aNgD0QAfjQ1lkH5kV28RtQEsTB7GzoNsjNARd1A6VwbjlLPDsMNlgwwn3jEqoZYrPNE/d4s4agyxmQKZQQuwvFYvyapoL07IgJlsW8JqPow6tFgLHvo/8OBql8Q6HIw1IQSThfPVGWHsB/Y3rUieDT1RpYVkpPNUHh15pCtUg2T8fdqmWf8IQD9nI/Bu0sRAfGBgvC+5yzhbo6nFWaHvMEzWjt6hlXgODoZKkAbaOZ9Tto/iueMpufgcFJWbCwdU47cqkW6cRA/sIbYiANfYeIhxmxEeWjlMb5vN3eh5Ya8mDf4TqGXebBtkbja6+py2vCweUW8jd5gSUqOHGYXrg7O38OC+B/rxoywnNvGtp8mSO0HQTpr8TwzNuyeqy0vVoxztFY3hmCzldWh6oGnQOHr191bO73RHbtVBcs5yXczwWCo+osksFZ2KczYzFHBhn3/U+zFC40oBrxzwUOG6c+CpPOinqbhwbqQwUtc6K3nuoJO4AMmrrnamIXjI96Y+YcGWQ5Ex1OZ3N2LSoXGXi/PrRmbcFuz2RMYVthQO6kRsbOpFVsWQcB4qFEVRnQ0Qju22YldOJV1XFViiarHQ45PT30R/0ZKKHIzvMeTmnEmXWq4YTyG2AvmH/mE2wdIrpk24FojykHGtg1CAdV5xaXsr4rXQP3fzm+fL5PVQy4TG8LQL41RbBdeECWB/1deEQYgzERtIuIDjWSOHrq7NO3u9dHBxvCm8AUSyvqnpjCSBg/jyiyXftAIWnnfZYn9Be/jLfHX9la6c3vLuf77K41ZPS8BQIP0oe1IcxX94b5RKUBRIEZWMrLAUvPJuVCYeH3St0gzWBB8f0yPWIQXCOphhWzwNMFIEx2rlUgihZI21GFd51MhEnjhMtvb+XAZ7bmcJDiU0+5ymebU6PhY9Ix1D0HeoV97Ym+zUdPGvxru8mwqbH0tlWk3d8Z8KDzZeBEEP8PjyepUHy/XeYLDZfZej4h2kmxrtPLyB1K83ZeE0N1xvTmgD9/wdQSwMEFAAAAAgAglRVXcz/R50rAAAAdgAAAAwAAAB2ZXJzaW9uLmpzb257v3t/NS+XAhAolaUWFWfm5ylZKShEQ4TQgZEOdnELHOIGmMKxvFy1vFwAUEsBAhQAFAAAAAgAWlRVXUbiWDFfNQAAer4AAA8AAAAAAAAAAAAAAAAAAAAAAHNjcmlwdHNcbWFpbi5qc1BLAQIUABQAAAAIABVUVV2XY8u5+AEAACYJAAANAAAAAAAAAAAAAAAAAIw1AABtYW5pZmVzdC5qc29uUEsBAhQAFAAAAAgAiwlVXbUiUvQXDQAAHQ8AAA0AAAAAAAAAAAAAAAAArzcAAHBhY2tfaWNvbi5wbmdQSwECFAAUAAAACAB7VFVdiFpDL88IAACnEQAACQAAAAAAAAAAAAAAAADxRAAAUkVBRE1FLm1kUEsBAhQAFAAAAAgAglRVXcz/R50rAAAAdgAAAAwAAAAAAAAAAAAAAAAA500AAHZlcnNpb24uanNvblBLBQYAAAAABQAFACQBAAA8TgAAAAA=
#@@RAB_PACK_END@@
