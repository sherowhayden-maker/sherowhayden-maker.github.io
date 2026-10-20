@echo off
title RAB Addon Updater
setlocal enabledelayedexpansion

echo.
echo   RAB addon updater - pulls the newest build and installs it in place.
echo   Run this whenever a new build ships (or anytime - it is always safe).
echo   Close Minecraft first (or sit at the main menu), then load your world.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$uuid='efb65a54-925f-4010-81df-94f716666141'; $roots=@(\"$env:LocalAppData\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\",\"$env:LocalAppData\Packages\Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe\LocalState\games\com.mojang\"); $bp=$null; foreach($r in $roots){ if(Test-Path $r){ $bp=Join-Path $r 'behavior_packs'; break } }; if(-not $bp){ Write-Host '  FAILED: could not find Minecraft data folder (is Bedrock installed on this PC?)'; exit 1 }; try { $z=Join-Path $env:TEMP 'rab-update.zip'; Invoke-WebRequest -Uri 'https://sherowhayden-maker.github.io/addons/RAB-Scoreboard.mcpack' -OutFile $z -UseBasicParsing; $x=Join-Path $env:TEMP 'rab-update-x'; if(Test-Path $x){ Remove-Item $x -Recurse -Force }; Expand-Archive -LiteralPath $z -DestinationPath $x -Force; if(-not (Test-Path (Join-Path $x 'manifest.json'))){ throw 'bad download - manifest missing' }; Get-ChildItem $bp -Directory -ErrorAction SilentlyContinue | ForEach-Object { $mf=Join-Path $_.FullName 'manifest.json'; if(Test-Path $mf){ try { $old=Get-Content $mf -Raw | ConvertFrom-Json; if($old.header.uuid -eq $uuid){ Remove-Item $_.FullName -Recurse -Force; Write-Host ('  removed old copy: ' + $_.Name) } } catch {} } }; $dest=Join-Path $bp 'RAB-Scoreboard'; New-Item -ItemType Directory -Force -Path $dest | Out-Null; Copy-Item (Join-Path $x '*') $dest -Recurse -Force; $m=Get-Content (Join-Path $x 'manifest.json') -Raw | ConvertFrom-Json; Write-Host ('  OK - installed ' + $m.header.name + ' v' + ($m.header.version -join '.')) } catch { Write-Host ('  FAILED: ' + $_.Exception.Message); exit 1 }"

if errorlevel 1 (
  echo   Update failed - check your internet and run it again.
) else (
  echo   Done! Start Minecraft and load your world - it is already updated.
)
echo.
pause
